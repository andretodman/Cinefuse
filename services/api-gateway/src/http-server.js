import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { createClient } from "redis";
import { parseBearerAuth } from "./auth.js";
import { createMcpHost } from "./mcp-host.js";
import {
  deleteProject,
  getProject,
  getShot,
  listCharacters,
  listAudioTracks,
  listJobs,
  listProjects,
  listScenes,
  listShots,
  saveJob,
  saveProject,
  saveScene,
  saveCharacter,
  saveAudioTrack,
  saveShot
} from "./project-store.js";

function json(response, status, payload) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
}

async function readBody(request) {
  let body = "";
  for await (const chunk of request) {
    body += chunk;
  }
  return body ? JSON.parse(body) : {};
}

function writeError(response, status, message, code) {
  return json(response, status, { error: message, code });
}

const RENDER_QUEUE_KEY = process.env.CINEFUSE_RENDER_QUEUE_KEY ?? "cinefuse:render_jobs";
const WORKER_AUTH_TOKEN = process.env.CINEFUSE_WORKER_TOKEN ?? "cinefuse-dev-worker-token";

function deriveThumbnailUrl(clipUrl) {
  if (typeof clipUrl !== "string" || clipUrl.length === 0) {
    return null;
  }
  return `${clipUrl}?thumb=1`;
}

function applyLegacyProjectsAliasHeaders(response, pathName) {
  if (pathName !== "/v1/projects") {
    return;
  }
  response.setHeader("x-cinefuse-deprecated-route", "/v1/projects");
  response.setHeader("x-cinefuse-canonical-route", "/api/v1/cinefuse/projects");
}

function applyLegacySparksAliasHeaders(response, pathName) {
  if (pathName !== "/v1/sparks/balance") {
    return;
  }
  response.setHeader("x-cinefuse-deprecated-route", "/v1/sparks/balance");
  response.setHeader("x-cinefuse-canonical-route", "/api/v1/cinefuse/sparks/balance");
}

export function createHttpServer() {
  const mcpHost = createMcpHost();
  const renderQueue = [];
  const projectSubscribers = new Map();
  let isProcessingRenderQueue = false;
  let redisClient;

  function getRedisClient() {
    if (process.env.NODE_ENV === "test" && process.env.CINEFUSE_USE_REDIS_IN_TESTS !== "true") {
      return null;
    }
    if (redisClient) {
      return redisClient;
    }
    const redisUrl = process.env.CINEFUSE_REDIS_URL ?? process.env.REDIS_URL;
    if (!redisUrl) {
      return null;
    }
    redisClient = createClient({ url: redisUrl });
    redisClient.on("error", () => {
      // Fall back to in-process queue if Redis is unavailable.
    });
    return redisClient;
  }

  function publishProjectEvent(projectId, payload) {
    const subscribers = projectSubscribers.get(projectId);
    if (!subscribers || subscribers.size === 0) {
      return;
    }
    const message = `data: ${JSON.stringify({
      ...payload,
      projectId,
      timestamp: new Date().toISOString()
    })}\n\n`;

    for (const response of subscribers) {
      try {
        response.write(message);
      } catch {
        subscribers.delete(response);
      }
    }

    if (subscribers.size === 0) {
      projectSubscribers.delete(projectId);
    }
  }

  async function processRenderTask(task) {
    const currentShot = await getShot(task.shotId, task.projectId);
    if (!currentShot) {
      await saveJob({
        id: task.jobId,
        status: "failed",
        outputPayload: { error: "shot not found during generation" }
      });
      publishProjectEvent(task.projectId, {
        type: "job_status_changed",
        jobId: task.jobId,
        shotId: task.shotId,
        status: "failed"
      });
      return;
    }

    await saveShot({
      ...currentShot,
      status: "generating"
    });
    await saveJob({
      id: task.jobId,
      status: "running"
    });
    publishProjectEvent(task.projectId, {
      type: "shot_status_changed",
      shotId: task.shotId,
      status: "generating"
    });
    publishProjectEvent(task.projectId, {
      type: "job_status_changed",
      jobId: task.jobId,
      shotId: task.shotId,
      status: "running"
    });

    try {
      const generation = await mcpHost.invoke("clip", "generate_clip", {
        shotId: task.shotId,
        projectId: task.projectId,
        prompt: currentShot.prompt,
        modelTier: currentShot.modelTier,
        userId: task.userId
      });

      await saveShot({
        ...currentShot,
        status: generation.status ?? "ready",
        clipUrl: generation.clipUrl ?? null,
        thumbnailUrl: deriveThumbnailUrl(generation.clipUrl ?? null),
        durationSec: generation.durationSec ?? currentShot.durationSec ?? 5
      });
      await saveJob({
        id: task.jobId,
        status: "done",
        outputPayload: {
          modelId: generation.modelId ?? null,
          clipUrl: generation.clipUrl ?? null,
          sparksCost: task.quote.sparksCost
        },
        costToUsCents: generation.costToUsCents ?? 0
      });
      publishProjectEvent(task.projectId, {
        type: "shot_status_changed",
        shotId: task.shotId,
        status: generation.status ?? "ready"
      });
      publishProjectEvent(task.projectId, {
        type: "job_status_changed",
        jobId: task.jobId,
        shotId: task.shotId,
        status: "done"
      });
    } catch (error) {
      await saveShot({
        ...currentShot,
        status: "failed"
      });
      await saveJob({
        id: task.jobId,
        status: "failed",
        outputPayload: {
          error: error instanceof Error ? error.message : "generation failed"
        }
      });
      publishProjectEvent(task.projectId, {
        type: "shot_status_changed",
        shotId: task.shotId,
        status: "failed"
      });
      publishProjectEvent(task.projectId, {
        type: "job_status_changed",
        jobId: task.jobId,
        shotId: task.shotId,
        status: "failed"
      });
      await mcpHost.invoke("billing", "credit", {
        userId: task.userId,
        amount: task.quote.sparksCost,
        idempotencyKey: `shot-generate-refund:${task.jobId}`,
        relatedResourceType: "shot",
        relatedResourceId: task.shotId
      });
    }
  }

  async function processRenderQueue() {
    if (isProcessingRenderQueue) {
      return;
    }
    isProcessingRenderQueue = true;
    try {
      while (renderQueue.length > 0) {
        const task = renderQueue.shift();
        if (!task) {
          continue;
        }
        await processRenderTask(task);
      }
    } finally {
      isProcessingRenderQueue = false;
    }
  }

  async function enqueueRenderTask(task) {
    const redis = getRedisClient();
    if (redis) {
      try {
        if (!redis.isOpen) {
          await redis.connect();
        }
        await redis.rPush(RENDER_QUEUE_KEY, JSON.stringify(task));
        return;
      } catch {
        // Fall through to in-process queue if Redis enqueue fails.
      }
    }

    renderQueue.push(task);
    queueMicrotask(() => {
      void processRenderQueue();
    });
  }

  return createServer(async (request, response) => {
    const method = request.method ?? "GET";
    const url = new URL(request.url ?? "/", "http://localhost");
    try {

      if (method === "POST" && url.pathname === "/api/v1/internal/render/process") {
        if (request.headers["x-cinefuse-worker-token"] !== WORKER_AUTH_TOKEN) {
          return writeError(response, 401, "unauthorized worker", "UNAUTHORIZED_WORKER");
        }
        const task = await readBody(request);
        await processRenderTask(task);
        return json(response, 200, { ok: true });
      }

      if (method === "GET" && url.pathname === "/health") {
        return json(response, 200, { ok: true, service: "api-gateway" });
      }

      if (method === "GET" && url.pathname === "/v1/mcp/servers") {
        return json(response, 200, { servers: mcpHost.listServers() });
      }

      if (method === "GET" && url.pathname === "/api/v1/cinefuse/health") {
        return json(response, 200, { ok: true, service: "api-gateway", domain: "cinefuse" });
      }

    const auth = parseBearerAuth(request.headers.authorization);
    if (!auth) {
      return writeError(response, 401, "unauthorized", "UNAUTHORIZED");
    }

    const projectEventsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/events$/);
    if (projectEventsMatch && method === "GET") {
      const projectId = decodeURIComponent(projectEventsMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }

      response.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        connection: "keep-alive",
        "x-accel-buffering": "no"
      });

      const subscribers = projectSubscribers.get(projectId) ?? new Set();
      subscribers.add(response);
      projectSubscribers.set(projectId, subscribers);

      publishProjectEvent(projectId, { type: "connected", status: "connected" });

      const keepAlive = setInterval(() => {
        try {
          response.write(": heartbeat\n\n");
        } catch {
          clearInterval(keepAlive);
        }
      }, 15000);

      request.on("close", () => {
        clearInterval(keepAlive);
        const current = projectSubscribers.get(projectId);
        if (!current) {
          return;
        }
        current.delete(response);
        if (current.size === 0) {
          projectSubscribers.delete(projectId);
        }
      });
      return;
    }

    if (
      method === "GET"
      && (url.pathname === "/api/v1/cinefuse/sparks/balance" || url.pathname === "/v1/sparks/balance")
    ) {
      applyLegacySparksAliasHeaders(response, url.pathname);
      const result = await mcpHost.invoke("billing", "get_balance", { userId: auth.userId });
      return json(response, 200, {
        userId: auth.userId,
        balance: result.balance
      });
    }

    if (method === "POST" && url.pathname === "/api/v1/cinefuse/sparks/debit") {
      const payload = await readBody(request);
      if (typeof payload.idempotencyKey !== "string" || payload.idempotencyKey.length === 0) {
        return writeError(response, 400, "idempotency key required", "IDEMPOTENCY_KEY_REQUIRED");
      }
      const amount = Number(payload.amount ?? 0);
      if (!Number.isFinite(amount) || amount < 0) {
        return writeError(response, 400, "invalid debit amount", "INVALID_DEBIT_AMOUNT");
      }
      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount,
        idempotencyKey: payload.idempotencyKey,
        relatedResourceType: payload.relatedResourceType ?? null,
        relatedResourceId: payload.relatedResourceId ?? null
      });
      const balanceResult = await mcpHost.invoke("billing", "get_balance", { userId: auth.userId });
      return json(response, 200, {
        ok: true,
        transaction: {
          kind: "debit",
          amount,
          idempotencyKey: payload.idempotencyKey,
          relatedResourceType: payload.relatedResourceType ?? null,
          relatedResourceId: payload.relatedResourceId ?? null
        },
        balance: balanceResult.balance
      });
    }

    if (method === "POST" && url.pathname === "/api/v1/cinefuse/sparks/credit") {
      const payload = await readBody(request);
      if (typeof payload.idempotencyKey !== "string" || payload.idempotencyKey.length === 0) {
        return writeError(response, 400, "idempotency key required", "IDEMPOTENCY_KEY_REQUIRED");
      }
      const amount = Number(payload.amount ?? 0);
      if (!Number.isFinite(amount) || amount < 0) {
        return writeError(response, 400, "invalid credit amount", "INVALID_CREDIT_AMOUNT");
      }
      await mcpHost.invoke("billing", "credit", {
        userId: auth.userId,
        amount,
        idempotencyKey: payload.idempotencyKey,
        relatedResourceType: payload.relatedResourceType ?? null,
        relatedResourceId: payload.relatedResourceId ?? null
      });
      const balanceResult = await mcpHost.invoke("billing", "get_balance", { userId: auth.userId });
      return json(response, 200, {
        ok: true,
        transaction: {
          kind: "credit",
          amount,
          idempotencyKey: payload.idempotencyKey,
          relatedResourceType: payload.relatedResourceType ?? null,
          relatedResourceId: payload.relatedResourceId ?? null
        },
        balance: balanceResult.balance
      });
    }

    if (
      method === "GET"
      && (url.pathname === "/api/v1/cinefuse/projects" || url.pathname === "/v1/projects")
    ) {
      applyLegacyProjectsAliasHeaders(response, url.pathname);
      return json(response, 200, {
        projects: await listProjects(auth.userId)
      });
    }

    if (
      method === "POST"
      && (url.pathname === "/api/v1/cinefuse/projects" || url.pathname === "/v1/projects")
    ) {
      applyLegacyProjectsAliasHeaders(response, url.pathname);
      const payload = await readBody(request);
      const project = await saveProject({
        id: payload.id ?? randomUUID(),
        ownerUserId: auth.userId,
        title: payload.title ?? "Untitled project",
        logline: payload.logline ?? "",
        targetDurationMinutes: payload.targetDurationMinutes ?? 5,
        tone: payload.tone ?? "drama"
      });

      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount: 0,
        idempotencyKey: `project-create:${project.id}`,
        relatedResourceType: "project",
        relatedResourceId: project.id
      });

      return json(response, 201, { project });
    }

    const projectDetailMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)$/);
    if (projectDetailMatch && method === "GET") {
      const projectId = decodeURIComponent(projectDetailMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { project });
    }
    if (projectDetailMatch && method === "DELETE") {
      const projectId = decodeURIComponent(projectDetailMatch[1]);
      const deleted = await deleteProject(projectId, auth.userId);
      if (!deleted) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { ok: true, deletedProjectId: projectId });
    }

    const scenesMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/scenes$/);
    if (scenesMatch && method === "GET") {
      const projectId = decodeURIComponent(scenesMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { scenes: await listScenes(projectId) });
    }
    if (scenesMatch && method === "POST") {
      const projectId = decodeURIComponent(scenesMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const scene = await saveScene({
        id: payload.id ?? randomUUID(),
        projectId,
        orderIndex: payload.orderIndex ?? 0,
        title: payload.title ?? "Untitled Scene",
        description: payload.description ?? "",
        mood: payload.mood ?? project.tone
      });
      return json(response, 201, { scene });
    }

    const reviseSceneMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/scenes\/([^/]+)$/);
    if (reviseSceneMatch && method === "POST") {
      const projectId = decodeURIComponent(reviseSceneMatch[1]);
      const sceneId = decodeURIComponent(reviseSceneMatch[2]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const revised = await mcpHost.invoke("script", "revise_scene", {
        sceneId,
        title: payload.title,
        description: payload.description,
        revision: payload.revision,
        mood: payload.mood ?? project.tone,
        orderIndex: payload.orderIndex ?? 0
      });
      const scene = await saveScene({
        id: sceneId,
        projectId,
        orderIndex: revised.scene.orderIndex ?? 0,
        title: revised.scene.title,
        description: revised.scene.description,
        mood: revised.scene.mood ?? project.tone
      });
      return json(response, 200, { scene });
    }

    const generateStoryboardMatch = url.pathname.match(
      /^\/api\/v1\/cinefuse\/projects\/([^/]+)\/storyboard\/generate$/
    );
    if (generateStoryboardMatch && method === "POST") {
      const projectId = decodeURIComponent(generateStoryboardMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const beatSheet = await mcpHost.invoke("script", "generate_beat_sheet", {
        logline: payload.logline ?? project.logline,
        targetDurationMinutes: payload.targetDurationMinutes ?? project.targetDurationMinutes,
        tone: payload.tone ?? project.tone
      });

      const scenes = [];
      for (const scene of beatSheet.scenes ?? []) {
        const savedScene = await saveScene({
          id: scene.id ?? randomUUID(),
          projectId,
          orderIndex: scene.orderIndex ?? 0,
          title: scene.title ?? "Untitled Scene",
          description: scene.description ?? "",
          mood: scene.mood ?? project.tone
        });
        scenes.push(savedScene);
      }

      return json(response, 200, {
        projectId,
        summary: beatSheet.summary ?? null,
        scenes
      });
    }

    const charactersMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/characters$/);
    if (charactersMatch && method === "GET") {
      const projectId = decodeURIComponent(charactersMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { characters: await listCharacters(projectId) });
    }
    if (charactersMatch && method === "POST") {
      const projectId = decodeURIComponent(charactersMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const characterId = payload.id ?? randomUUID();
      const created = await mcpHost.invoke("character", "create_character", {
        id: characterId,
        projectId,
        name: payload.name ?? "Untitled Character",
        description: payload.description ?? ""
      });
      const character = await saveCharacter({
        id: characterId,
        projectId,
        name: created.character?.name ?? payload.name ?? "Untitled Character",
        description: created.character?.description ?? payload.description ?? "",
        status: created.character?.status ?? "draft",
        previewUrl: created.character?.previewUrl ?? null,
        consistencyScore: created.character?.consistencyScore ?? null,
        consistencyThreshold: created.character?.consistencyThreshold ?? null,
        consistencyPassed: created.character?.consistencyPassed ?? false
      });
      return json(response, 201, { character });
    }

    const trainCharacterMatch = url.pathname.match(
      /^\/api\/v1\/cinefuse\/projects\/([^/]+)\/characters\/([^/]+)\/train$/
    );
    if (trainCharacterMatch && method === "POST") {
      const projectId = decodeURIComponent(trainCharacterMatch[1]);
      const characterId = decodeURIComponent(trainCharacterMatch[2]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const trained = await mcpHost.invoke("character", "train_identity", {
        projectId,
        characterId
      });
      const trainingSparksCost = Number(trained.sparksCost ?? 0);
      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount: trainingSparksCost,
        idempotencyKey: `character-train:${characterId}`,
        relatedResourceType: "character",
        relatedResourceId: characterId
      });
      const character = await saveCharacter({
        id: characterId,
        projectId,
        name: trained.character?.name ?? "Untitled Character",
        description: trained.character?.description ?? "",
        status: trained.character?.status ?? "trained",
        previewUrl: trained.character?.previewUrl ?? null,
        consistencyScore: trained.character?.consistencyScore ?? null,
        consistencyThreshold: trained.character?.consistencyThreshold ?? null,
        consistencyPassed: trained.character?.consistencyPassed ?? false
      });
      return json(response, 200, { character, sparksCost: trainingSparksCost });
    }

    const shotsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots$/);
    const timelineMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/timeline$/);
    const timelineReorderMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/timeline\/reorder$/);
    const audioTracksMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/audio-tracks$/);
    const dialogueAudioMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/audio\/dialogue$/);
    const scoreAudioMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/audio\/score$/);
    const sfxAudioMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/audio\/sfx$/);
    const mixAudioMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/audio\/mix$/);
    const lipsyncAudioMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/audio\/lipsync$/);
    const stitchPreviewMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/stitch\/preview$/);
    const stitchFinalMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/stitch\/final$/);
    const stitchTransitionsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/stitch\/transitions$/);
    const stitchColorMatchMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/stitch\/color-match$/);
    const stitchCaptionsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/stitch\/captions\/bake$/);
    const stitchLoudnessMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/stitch\/loudness\/normalize$/);
    const exportFinalMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/export\/final$/);
    const shotQuoteMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots\/quote$/);
    if (timelineMatch && method === "GET") {
      const projectId = decodeURIComponent(timelineMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, {
        projectId,
        shots: await listShots(projectId),
        audioTracks: await listAudioTracks(projectId)
      });
    }
    if (timelineReorderMatch && method === "PUT") {
      const projectId = decodeURIComponent(timelineReorderMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      if (!Array.isArray(payload.shotIds) || payload.shotIds.length === 0) {
        return writeError(response, 400, "shotIds required", "SHOT_IDS_REQUIRED");
      }
      const existingShots = await listShots(projectId);
      const byId = new Map(existingShots.map((shot) => [shot.id, shot]));
      for (let index = 0; index < payload.shotIds.length; index += 1) {
        const shotId = payload.shotIds[index];
        const shot = byId.get(shotId);
        if (!shot) {
          continue;
        }
        await saveShot({
          ...shot,
          orderIndex: index
        });
      }
      return json(response, 200, { shots: await listShots(projectId) });
    }
    if (audioTracksMatch && method === "GET") {
      const projectId = decodeURIComponent(audioTracksMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { audioTracks: await listAudioTracks(projectId) });
    }
    if (audioTracksMatch && method === "POST") {
      const projectId = decodeURIComponent(audioTracksMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const track = await saveAudioTrack({
        id: payload.id ?? randomUUID(),
        projectId,
        shotId: payload.shotId ?? null,
        kind: payload.kind ?? "score",
        title: payload.title ?? "Untitled Track",
        sourceUrl: payload.sourceUrl ?? null,
        waveformUrl: payload.waveformUrl ?? null,
        laneIndex: Number(payload.laneIndex ?? 0),
        startMs: Number(payload.startMs ?? 0),
        durationMs: Number(payload.durationMs ?? 0),
        status: payload.status ?? "draft"
      });
      return json(response, 201, { audioTrack: track });
    }
    const audioToolByPath = dialogueAudioMatch
      ? "generate_dialogue"
      : scoreAudioMatch
        ? "generate_score"
        : sfxAudioMatch
          ? "generate_sfx"
          : mixAudioMatch
            ? "mix_scene"
            : lipsyncAudioMatch
              ? "lipsync"
              : null;
    const audioProjectMatch = dialogueAudioMatch || scoreAudioMatch || sfxAudioMatch || mixAudioMatch || lipsyncAudioMatch;
    if (audioProjectMatch && method === "POST" && audioToolByPath) {
      const projectId = decodeURIComponent(audioProjectMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const audioResult = await mcpHost.invoke("audio", audioToolByPath, {
        ...payload,
        projectId
      });
      const sparksCost = Number(audioResult.track?.sparksCost ?? 15);
      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount: sparksCost,
        idempotencyKey: `${audioToolByPath}:${projectId}:${payload.shotId ?? "none"}:${payload.startMs ?? 0}`,
        relatedResourceType: "project",
        relatedResourceId: projectId
      });
      const track = await saveAudioTrack({
        id: audioResult.track?.id ?? randomUUID(),
        projectId,
        shotId: payload.shotId ?? null,
        kind: audioResult.track?.kind ?? "audio",
        title: payload.title ?? `${audioResult.track?.kind ?? "Audio"} track`,
        sourceUrl: audioResult.track?.sourceUrl ?? null,
        waveformUrl: audioResult.track?.waveformUrl ?? null,
        laneIndex: audioResult.track?.laneIndex ?? Number(payload.laneIndex ?? 0),
        startMs: audioResult.track?.startMs ?? Number(payload.startMs ?? 0),
        durationMs: audioResult.track?.durationMs ?? Number(payload.durationMs ?? 0),
        status: audioResult.track?.status ?? "ready"
      });
      const job = await saveJob({
        id: randomUUID(),
        projectId,
        shotId: payload.shotId ?? null,
        kind: "audio",
        status: "done",
        inputPayload: payload,
        outputPayload: { track, sparksCost },
        costToUsCents: Number(audioResult.track?.costToUsCents ?? 0)
      });
      publishProjectEvent(projectId, {
        type: "job_status_changed",
        jobId: job.id,
        shotId: track.shotId ?? null,
        status: "done"
      });
      return json(response, 200, { audioTrack: track, job, sparksCost });
    }
    const stitchToolByPath = stitchPreviewMatch
      ? "preview_stitch"
      : stitchFinalMatch
        ? "final_stitch"
        : stitchTransitionsMatch
          ? "apply_transitions"
          : stitchColorMatchMatch
            ? "color_match"
            : stitchCaptionsMatch
              ? "bake_captions"
              : stitchLoudnessMatch
                ? "loudness_normalize"
                : null;
    const stitchProjectMatch = stitchPreviewMatch
      || stitchFinalMatch
      || stitchTransitionsMatch
      || stitchColorMatchMatch
      || stitchCaptionsMatch
      || stitchLoudnessMatch;
    if (stitchProjectMatch && method === "POST" && stitchToolByPath) {
      const projectId = decodeURIComponent(stitchProjectMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const timelineShots = await listShots(projectId);
      const timelineAudioTracks = await listAudioTracks(projectId);
      const stitched = await mcpHost.invoke("stitch", stitchToolByPath, {
        ...payload,
        projectId,
        shots: timelineShots,
        audioTracks: timelineAudioTracks
      });
      const job = await saveJob({
        id: randomUUID(),
        projectId,
        kind: "stitch",
        status: "done",
        inputPayload: payload,
        outputPayload: {
          operation: stitchToolByPath,
          ...(stitched.result ?? {})
        },
        costToUsCents: Number(stitched.result?.costToUsCents ?? 0)
      });
      return json(response, 200, { stitch: stitched.result, job });
    }
    if (exportFinalMatch && method === "POST") {
      const projectId = decodeURIComponent(exportFinalMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const timelineShots = await listShots(projectId);
      const timelineAudioTracks = await listAudioTracks(projectId);
      const stitched = await mcpHost.invoke("stitch", "final_stitch", {
        projectId,
        shots: timelineShots,
        audioTracks: timelineAudioTracks
      });
      const exported = await mcpHost.invoke("export", "encode_final", {
        projectId,
        stitchedUrl: stitched.result?.stitchedUrl ?? null,
        ...payload
      });
      const includeArchive = payload.includeArchive === true;
      const publishTarget = typeof payload.publishTarget === "string"
        ? payload.publishTarget
        : payload.publishToPubfuse === true
          ? "pubfuse"
          : "none";
      const publishToPubfuse = publishTarget === "pubfuse";
      const archiveResult = includeArchive
        ? await mcpHost.invoke("export", "archive_project", {
          projectId,
          fileUrl: exported.export?.fileUrl ?? null,
          stitchedUrl: stitched.result?.stitchedUrl ?? null,
          sparksCost: 0,
          costToUsCents: 0
        })
        : null;
      const publishResult = publishToPubfuse
        ? await mcpHost.invoke("export", "publish_to_pubfuse_stream", {
          projectId,
          fileUrl: exported.export?.fileUrl ?? null,
          stitchedUrl: stitched.result?.stitchedUrl ?? null,
          sparksCost: 0,
          costToUsCents: 0
        })
        : null;
      const sparksCost = Number(exported.export?.sparksCost ?? 40);
      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount: sparksCost,
        idempotencyKey: `export-final:${projectId}`,
        relatedResourceType: "project",
        relatedResourceId: projectId
      });
      const job = await saveJob({
        id: randomUUID(),
        projectId,
        kind: "export",
        status: "done",
        inputPayload: payload,
        outputPayload: {
          stitchedUrl: stitched.result?.stitchedUrl ?? null,
          fileUrl: exported.export?.fileUrl ?? null,
          archiveUrl: archiveResult?.export?.archiveUrl ?? exported.export?.archiveUrl ?? null,
          publishedUrl: publishResult?.export?.fileUrl ?? null,
          sparksCost,
          includeArchive,
          publishTarget,
          publishToPubfuse
        },
        costToUsCents: Number(exported.export?.costToUsCents ?? 0)
          + Number(stitched.result?.costToUsCents ?? 0)
          + Number(archiveResult?.export?.costToUsCents ?? 0)
          + Number(publishResult?.export?.costToUsCents ?? 0)
      });
      return json(response, 200, {
        export: exported.export,
        stitch: stitched.result,
        archive: archiveResult?.export ?? null,
        published: publishResult?.export ?? null,
        job
      });
    }
    if (shotQuoteMatch && method === "POST") {
      const projectId = decodeURIComponent(shotQuoteMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      if (typeof payload.prompt !== "string" || payload.prompt.trim().length === 0) {
        return writeError(response, 400, "prompt required", "PROMPT_REQUIRED");
      }
      const modelTier = payload.modelTier ?? "budget";
      const quote = await mcpHost.invoke("clip", "quote_clip", {
        prompt: payload.prompt,
        modelTier,
        projectId,
        characterLocks: payload.characterLocks ?? [],
        userId: auth.userId
      });
      return json(response, 200, {
        quote: {
          sparksCost: quote.sparksCost,
          modelTier: quote.modelTier,
          modelId: quote.modelId,
          estimatedDurationSec: quote.estimatedDurationSec
        }
      });
    }
    if (shotsMatch && method === "GET") {
      const projectId = decodeURIComponent(shotsMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { shots: await listShots(projectId) });
    }
    if (shotsMatch && method === "POST") {
      const projectId = decodeURIComponent(shotsMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const existingShots = await listShots(projectId);
      const shot = await saveShot({
        id: payload.id ?? randomUUID(),
        projectId,
        prompt: payload.prompt ?? "",
        modelTier: payload.modelTier ?? "budget",
        status: payload.status ?? "draft",
        clipUrl: payload.clipUrl ?? null,
        thumbnailUrl: payload.thumbnailUrl ?? deriveThumbnailUrl(payload.clipUrl ?? null),
        durationSec: payload.durationSec ?? null,
        audioRefs: payload.audioRefs ?? [],
        orderIndex: Number(payload.orderIndex ?? existingShots.length),
        characterLocks: payload.characterLocks ?? []
      });
      return json(response, 201, { shot });
    }

    const shotGenerateMatch = url.pathname.match(
      /^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots\/([^/]+)\/generate$/
    );
    if (shotGenerateMatch && method === "POST") {
      const projectId = decodeURIComponent(shotGenerateMatch[1]);
      const shotId = decodeURIComponent(shotGenerateMatch[2]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const shot = await getShot(shotId, projectId);
      if (!shot) {
        return writeError(response, 404, "shot not found", "SHOT_NOT_FOUND");
      }
      if (shot.status === "queued" || shot.status === "generating") {
        return writeError(response, 409, "shot generation already in progress", "SHOT_ALREADY_GENERATING");
      }

      const quote = await mcpHost.invoke("clip", "quote_clip", {
        shotId,
        projectId,
        prompt: shot.prompt,
        modelTier: shot.modelTier,
        characterLocks: shot.characterLocks ?? [],
        userId: auth.userId
      });
      const payload = await readBody(request);
      const jobId = randomUUID();
      const generationIdempotencyKey = payload.idempotencyKey ?? `shot-generate:${shotId}:${jobId}`;

      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount: quote.sparksCost,
        idempotencyKey: generationIdempotencyKey,
        relatedResourceType: "shot",
        relatedResourceId: shotId
      });

      const queuedShot = await saveShot({
        ...shot,
        status: "queued"
      });
      const job = await saveJob({
        id: jobId,
        projectId,
        shotId: queuedShot.id,
        kind: "clip",
        status: "queued",
        inputPayload: {
          prompt: queuedShot.prompt,
          modelTier: queuedShot.modelTier,
          sparksCost: quote.sparksCost
        },
        outputPayload: {},
        costToUsCents: 0
      });
      publishProjectEvent(projectId, {
        type: "shot_status_changed",
        shotId,
        status: "queued"
      });
      publishProjectEvent(projectId, {
        type: "job_status_changed",
        jobId,
        shotId,
        status: "queued"
      });
      await enqueueRenderTask({
        jobId,
        shotId,
        projectId,
        userId: auth.userId,
        quote,
        debitIdempotencyKey: generationIdempotencyKey
      });

      return json(response, 200, {
        shot: queuedShot,
        job,
        quote: {
          sparksCost: quote.sparksCost,
          modelTier: quote.modelTier,
          modelId: quote.modelId,
          estimatedDurationSec: quote.estimatedDurationSec,
          idempotencyKey: generationIdempotencyKey
        }
      });
    }

    const jobsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/jobs$/);
    if (jobsMatch && method === "GET") {
      const projectId = decodeURIComponent(jobsMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { jobs: await listJobs(projectId) });
    }
    if (jobsMatch && method === "POST") {
      const projectId = decodeURIComponent(jobsMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const job = await saveJob({
        id: payload.id ?? randomUUID(),
        projectId,
        shotId: payload.shotId ?? null,
        kind: payload.kind ?? "clip",
        status: payload.status ?? "queued",
        inputPayload: payload.inputPayload ?? {},
        outputPayload: payload.outputPayload ?? {},
        costToUsCents: payload.costToUsCents ?? 0
      });
      return json(response, 201, { job });
    }

    if (method === "POST" && url.pathname === "/v1/mcp/invoke") {
      const payload = await readBody(request);
      const result = await mcpHost.invoke(payload.server, payload.tool, {
        ...payload.input,
        cinefuse_user_id: auth.userId
      });
      return json(response, 200, result);
    }

      return writeError(response, 404, "not_found", "NOT_FOUND");
    } catch (error) {
      const message = error instanceof Error ? error.message : "request handling failed";
      console.error("[api-gateway] unhandled request error", {
        method,
        path: url.pathname,
        message
      });
      if (!response.headersSent) {
        return writeError(response, 500, message, "INTERNAL_ERROR");
      }
      try {
        response.end();
      } catch {
        // no-op
      }
    }
  });
}
