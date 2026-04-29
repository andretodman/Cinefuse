import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { createClient } from "redis";
import { parseBearerAuth } from "./auth.js";
import { createMcpHost } from "./mcp-host.js";
import {
  deleteJob,
  deleteProject,
  deleteShot,
  getJob,
  getProject,
  getShot,
  listCharacters,
  listAudioTracks,
  listJobs,
  listProjects,
  listScenes,
  listShots,
  listSoundBlueprints,
  saveJob,
  saveProject,
  saveScene,
  saveCharacter,
  saveAudioTrack,
  saveShot,
  saveSoundBlueprint
} from "./project-store.js";

function json(response, status, payload) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
}

function html(response, status, payload) {
  response.writeHead(status, { "content-type": "text/html; charset=utf-8" });
  response.end(payload);
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

function parseFalContext(errorMessage) {
  if (typeof errorMessage !== "string") {
    return null;
  }
  const marker = "fal_context=";
  const markerIndex = errorMessage.indexOf(marker);
  if (markerIndex < 0) {
    return null;
  }
  const raw = errorMessage.slice(markerIndex + marker.length).trim();
  if (!raw.startsWith("{") || !raw.endsWith("}")) {
    return null;
  }
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

function coerceProviderStatusCode(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
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

function renderLandingPage() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Cinefuse</title>
    <style>
      :root {
        color-scheme: dark;
      }
      body {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif;
        background: #0b0f16;
        color: #e8eef7;
      }
      .wrap {
        max-width: 980px;
        margin: 0 auto;
        padding: 48px 20px 64px;
      }
      .badge {
        display: inline-block;
        border: 1px solid #2d3b52;
        border-radius: 999px;
        padding: 6px 12px;
        color: #a6bbde;
        font-size: 13px;
      }
      h1 {
        margin: 16px 0 8px;
        font-size: clamp(34px, 6vw, 56px);
        line-height: 1.05;
      }
      .sub {
        color: #b8c7de;
        font-size: 18px;
        max-width: 760px;
      }
      .row {
        margin-top: 24px;
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
      }
      a.button {
        text-decoration: none;
        font-weight: 600;
        border-radius: 10px;
        padding: 11px 16px;
      }
      a.primary {
        background: #2f7cff;
        color: white;
      }
      a.secondary {
        border: 1px solid #2d3b52;
        color: #cfe0ff;
      }
      .grid {
        margin-top: 36px;
        display: grid;
        gap: 14px;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      }
      .card {
        border: 1px solid #253248;
        border-radius: 14px;
        padding: 16px;
        background: #111827;
      }
      .card h3 {
        margin: 0 0 8px;
        font-size: 16px;
      }
      .card p {
        margin: 0;
        color: #aebfd9;
        font-size: 14px;
      }
      footer {
        margin-top: 40px;
        color: #8ea2c1;
        font-size: 13px;
      }
    </style>
  </head>
  <body>
    <main class="wrap">
      <span class="badge">Cinefuse by Pubfuse</span>
      <h1>Generate, edit, and export cinematic clips.</h1>
      <p class="sub">
        Cinefuse is an AI video editor for creators. Draft shots, generate clips, assemble timelines, and export finished cuts from one workspace.
      </p>
      <div class="row">
        <a class="button primary" href="/docs">Read Docs</a>
        <a class="button secondary" href="/api/v1/cinefuse/health">API Health</a>
      </div>
      <section class="grid" aria-label="Product sections">
        <article class="card">
          <h3>About</h3>
          <p>Built for rapid story iteration with prompt-to-clip workflows and timeline-aware assembly.</p>
        </article>
        <article class="card">
          <h3>Product</h3>
          <p>Shots, jobs, audio lanes, and export operations coordinated through Cinefuse MCP servers.</p>
        </article>
        <article class="card">
          <h3>Developer Docs</h3>
          <p>Setup, API contract, architecture docs, and milestone plans for local and cloud environments.</p>
        </article>
      </section>
      <footer>
        Looking for machine-readable APIs? Use the <code>/api/v1/cinefuse/*</code> routes with authorization.
      </footer>
    </main>
  </body>
</html>`;
}

function renderDocsPage() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Cinefuse Docs</title>
    <style>
      body {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif;
        background: #0b0f16;
        color: #e8eef7;
      }
      .wrap {
        max-width: 900px;
        margin: 0 auto;
        padding: 42px 20px 64px;
      }
      h1 { margin-top: 0; font-size: 36px; }
      p { color: #b7c7dd; }
      ul {
        margin: 18px 0 0;
        padding: 0;
        list-style: none;
        display: grid;
        gap: 10px;
      }
      a {
        display: block;
        text-decoration: none;
        color: #cfe0ff;
        border: 1px solid #2b3a52;
        border-radius: 10px;
        padding: 12px 14px;
        background: #111827;
      }
      a:hover { border-color: #3f5680; }
      .back {
        margin-top: 18px;
        display: inline-block;
        color: #9eb3d7;
      }
    </style>
  </head>
  <body>
    <main class="wrap">
      <h1>Cinefuse Docs</h1>
      <p>Documentation index for Cinefuse architecture, API contracts, and implementation milestones.</p>
      <ul>
        <li><a href="/api/v1/cinefuse/health">API Health Endpoint</a></li>
        <li><a href="https://github.com/atodman/Cinefuse/blob/main/PLAN.md">PLAN.md</a></li>
        <li><a href="https://github.com/atodman/Cinefuse/blob/main/MILESTONES.md">MILESTONES.md</a></li>
        <li><a href="https://github.com/atodman/Cinefuse/blob/main/docs/CINEFUSE-API-CONTRACT.md">CINEFUSE-API-CONTRACT.md</a></li>
      </ul>
      <a class="back" href="/">← Back to Cinefuse home</a>
    </main>
  </body>
</html>`;
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

  async function updateRenderJobProgress({ projectId, jobId, shotId, status = "running", progressPct }) {
    try {
      await saveJob({
        id: jobId,
        status,
        progressPct,
        outputPayload: {
          invokeState: status === "failed" ? "failed" : "running",
          lastProgressAt: new Date().toISOString()
        }
      });
    } catch (error) {
      console.error("[render] progress save failed", {
        projectId,
        shotId,
        jobId,
        status,
        progressPct,
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
    publishProjectEvent(projectId, {
      type: "job_status_changed",
      jobId,
      shotId,
      status,
      progressPct
    });
  }

  async function processRenderTask(task) {
    console.info("[render] task started", {
      projectId: task.projectId,
      shotId: task.shotId,
      jobId: task.jobId
    });
    const currentShot = await getShot(task.shotId, task.projectId);
    if (!currentShot) {
      await saveJob({
        id: task.jobId,
        status: "failed",
        progressPct: 0,
        outputPayload: { error: "shot not found during generation" }
      });
      publishProjectEvent(task.projectId, {
        type: "job_status_changed",
        jobId: task.jobId,
        shotId: task.shotId,
        status: "failed",
        progressPct: 0
      });
      return;
    }

    await saveShot({
      ...currentShot,
      status: "generating"
    });
    await saveJob({
      id: task.jobId,
      status: "running",
      progressPct: 15,
      outputPayload: {
        invokeState: "running",
        apiInvokeStartedAt: new Date().toISOString()
      }
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
      status: "running",
      progressPct: 15
    });

    let runningProgress = 15;
    const progressTimer = setInterval(() => {
      if (runningProgress >= 90) {
        return;
      }
      runningProgress = Math.min(90, runningProgress + 10);
      console.info("[render] progress tick", {
        projectId: task.projectId,
        shotId: task.shotId,
        jobId: task.jobId,
        progressPct: runningProgress
      });
      void updateRenderJobProgress({
        projectId: task.projectId,
        jobId: task.jobId,
        shotId: task.shotId,
        status: "running",
        progressPct: runningProgress
      });
    }, 4000);

    try {
      console.info("[render] invoking clip.generate_clip", {
        projectId: task.projectId,
        shotId: task.shotId,
        jobId: task.jobId,
        modelTier: currentShot.modelTier
      });
      const generation = await mcpHost.invoke("clip", "generate_clip", {
        shotId: task.shotId,
        projectId: task.projectId,
        prompt: currentShot.prompt,
        modelTier: currentShot.modelTier,
        userId: task.userId
      });
      clearInterval(progressTimer);
      console.info("[render] clip.generate_clip completed", {
        projectId: task.projectId,
        shotId: task.shotId,
        jobId: task.jobId,
        clipUrl: generation.clipUrl ?? null
      });

      await saveShot({
        ...currentShot,
        status: "ready",
        clipUrl: generation.clipUrl ?? null,
        thumbnailUrl: deriveThumbnailUrl(generation.clipUrl ?? null),
        durationSec: generation.durationSec ?? currentShot.durationSec ?? 5
      });
      await saveJob({
        id: task.jobId,
        outputPayload: {
          modelId: generation.modelId ?? null,
          requestId: generation.requestId ?? null,
          falEndpoint: generation.falEndpoint ?? null,
          falStatusUrl: generation.falStatusUrl ?? null,
          clipUrl: generation.clipUrl ?? null,
          sparksCost: task.quote.sparksCost,
          invokeState: "done",
          apiInvokeFinishedAt: new Date().toISOString()
        },
        costToUsCents: generation.costToUsCents ?? 0
      });
      await updateRenderJobProgress({
        projectId: task.projectId,
        jobId: task.jobId,
        shotId: task.shotId,
        status: "done",
        progressPct: 100
      });
      publishProjectEvent(task.projectId, {
        type: "shot_status_changed",
        shotId: task.shotId,
        status: "ready"
      });
      console.info("[render] task completed", {
        projectId: task.projectId,
        shotId: task.shotId,
        jobId: task.jobId
      });
    } catch (error) {
      clearInterval(progressTimer);
      const message = error instanceof Error ? error.message : "generation failed";
      const falContext = parseFalContext(message);
      console.error("[render] task failed", {
        projectId: task.projectId,
        shotId: task.shotId,
        jobId: task.jobId,
        message,
        falContext
      });
      await saveShot({
        ...currentShot,
        status: "failed"
      });
      await saveJob({
        id: task.jobId,
        outputPayload: {
          error: message,
          requestId: typeof falContext?.requestId === "string" ? falContext.requestId : null,
          falEndpoint: typeof falContext?.endpoint === "string" ? falContext.endpoint : null,
          falStatusUrl: typeof falContext?.statusUrl === "string" ? falContext.statusUrl : null,
          providerStatusCode: coerceProviderStatusCode(falContext?.statusCode),
          providerResponseSnippet: typeof falContext?.responseSnippet === "string" ? falContext.responseSnippet : null,
          invokeState: "failed",
          timeout: /timeout/i.test(message),
          apiInvokeFinishedAt: new Date().toISOString()
        }
      });
      await updateRenderJobProgress({
        projectId: task.projectId,
        jobId: task.jobId,
        shotId: task.shotId,
        status: "failed",
        progressPct: 0
      });
      publishProjectEvent(task.projectId, {
        type: "shot_status_changed",
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

  async function queueShotGeneration({ projectId, shot, userId, idempotencyKey }) {
    const quote = await mcpHost.invoke("clip", "quote_clip", {
      shotId: shot.id,
      projectId,
      prompt: shot.prompt,
      modelTier: shot.modelTier,
      characterLocks: shot.characterLocks ?? [],
      userId
    });
    const jobId = randomUUID();
    const generationIdempotencyKey = idempotencyKey ?? `shot-generate:${shot.id}:${jobId}`;

    await mcpHost.invoke("billing", "debit", {
      userId,
      amount: quote.sparksCost,
      idempotencyKey: generationIdempotencyKey,
      relatedResourceType: "shot",
      relatedResourceId: shot.id
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
      progressPct: 0,
      inputPayload: {
        prompt: queuedShot.prompt,
        modelTier: queuedShot.modelTier,
        sparksCost: quote.sparksCost,
        idempotencyKey: generationIdempotencyKey,
        apiRequestSentAt: new Date().toISOString()
      },
      outputPayload: {
        invokeState: "queued"
      },
      costToUsCents: 0
    });
    publishProjectEvent(projectId, {
      type: "shot_status_changed",
      shotId: shot.id,
      status: "queued",
      progressPct: 0
    });
    publishProjectEvent(projectId, {
      type: "job_status_changed",
      jobId,
      shotId: shot.id,
      status: "queued",
      progressPct: 0
    });

    await enqueueRenderTask({
      jobId,
      shotId: shot.id,
      projectId,
      userId,
      quote,
      debitIdempotencyKey: generationIdempotencyKey
    });

    return { queuedShot, job, quote, generationIdempotencyKey };
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

      if (method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
        return html(response, 200, renderLandingPage());
      }

      if (method === "GET" && (url.pathname === "/docs" || url.pathname === "/docs/")) {
        return html(response, 200, renderDocsPage());
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
    if (projectDetailMatch && method === "PATCH") {
      const projectId = decodeURIComponent(projectDetailMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const title = typeof payload.title === "string" ? payload.title.trim() : "";
      if (title.length === 0) {
        return writeError(response, 400, "title required", "TITLE_REQUIRED");
      }
      const updated = await saveProject({
        ...project,
        title
      });
      return json(response, 200, { project: updated });
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
    const exportAudioMixMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/export\/audio-mix$/);
    const soundBlueprintsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/sound-blueprints$/);
    const shotQuoteMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots\/quote$/);
    const shotDetailMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots\/([^/]+)$/);
    const shotRetryMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots\/([^/]+)\/retry$/);
    const jobDetailMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/jobs\/([^/]+)$/);
    const jobRetryMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/jobs\/([^/]+)\/retry$/);
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
    if (soundBlueprintsMatch && method === "GET") {
      const projectId = decodeURIComponent(soundBlueprintsMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { soundBlueprints: await listSoundBlueprints(projectId) });
    }
    if (soundBlueprintsMatch && method === "POST") {
      const projectId = decodeURIComponent(soundBlueprintsMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const blueprint = await saveSoundBlueprint({
        id: payload.id ?? randomUUID(),
        projectId,
        name: typeof payload.name === "string" ? payload.name : "Sound blueprint",
        templateId: typeof payload.templateId === "string" ? payload.templateId : null,
        referenceFileIds: Array.isArray(payload.referenceFileIds) ? payload.referenceFileIds : []
      });
      return json(response, 201, { soundBlueprint: blueprint });
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
    if (exportAudioMixMatch && method === "POST") {
      const projectId = decodeURIComponent(exportAudioMixMatch[1]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const timelineAudioTracks = await listAudioTracks(projectId);
      const exported = await mcpHost.invoke("export", "encode_audio_mixdown", {
        projectId,
        audioTracks: timelineAudioTracks
      });
      const sparksCost = Number(exported.export?.sparksCost ?? 18);
      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount: sparksCost,
        idempotencyKey: `export-audio-mix:${projectId}`,
        relatedResourceType: "project",
        relatedResourceId: projectId
      });
      const job = await saveJob({
        id: randomUUID(),
        projectId,
        kind: "audio_export",
        status: "done",
        inputPayload: {},
        outputPayload: {
          fileUrl: exported.export?.fileUrl ?? null,
          sparksCost,
          operation: "encode_audio_mixdown",
          costToUsCents: Number(exported.export?.costToUsCents ?? 0)
        },
        costToUsCents: Number(exported.export?.costToUsCents ?? 0)
      });
      return json(response, 200, {
        job,
        export: {
          fileUrl: exported.export?.fileUrl ?? null,
          sparksCost,
          costToUsCents: Number(exported.export?.costToUsCents ?? 0)
        }
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
    if (shotDetailMatch && method === "DELETE") {
      const projectId = decodeURIComponent(shotDetailMatch[1]);
      const shotId = decodeURIComponent(shotDetailMatch[2]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const deleted = await deleteShot(shotId, projectId);
      if (!deleted) {
        return writeError(response, 404, "shot not found", "SHOT_NOT_FOUND");
      }
      publishProjectEvent(projectId, {
        type: "shot_deleted",
        shotId
      });
      return json(response, 200, { ok: true, deletedShotId: shotId });
    }
    if (shotRetryMatch && method === "POST") {
      const projectId = decodeURIComponent(shotRetryMatch[1]);
      const shotId = decodeURIComponent(shotRetryMatch[2]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const shot = await getShot(shotId, projectId);
      if (!shot) {
        return writeError(response, 404, "shot not found", "SHOT_NOT_FOUND");
      }
      if (shot.status !== "failed") {
        return json(response, 409, {
          error: "only failed shots can be retried",
          code: "SHOT_RETRY_CONFLICT",
          currentStatus: shot.status
        });
      }
      const payload = await readBody(request);
      const result = await queueShotGeneration({
        projectId,
        shot,
        userId: auth.userId,
        idempotencyKey: payload.idempotencyKey
      });
      return json(response, 200, {
        shot: result.queuedShot,
        job: result.job,
        quote: {
          sparksCost: result.quote.sparksCost,
          modelTier: result.quote.modelTier,
          modelId: result.quote.modelId,
          estimatedDurationSec: result.quote.estimatedDurationSec,
          idempotencyKey: result.generationIdempotencyKey
        }
      });
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

      const payload = await readBody(request);
      const result = await queueShotGeneration({
        projectId,
        shot,
        userId: auth.userId,
        idempotencyKey: payload.idempotencyKey
      });

      return json(response, 200, {
        shot: result.queuedShot,
        job: result.job,
        quote: {
          sparksCost: result.quote.sparksCost,
          modelTier: result.quote.modelTier,
          modelId: result.quote.modelId,
          estimatedDurationSec: result.quote.estimatedDurationSec,
          idempotencyKey: result.generationIdempotencyKey
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
        progressPct: payload.progressPct ?? 0,
        inputPayload: payload.inputPayload ?? {},
        outputPayload: payload.outputPayload ?? {},
        costToUsCents: payload.costToUsCents ?? 0
      });
      return json(response, 201, { job });
    }
    if (jobDetailMatch && method === "DELETE") {
      const projectId = decodeURIComponent(jobDetailMatch[1]);
      const jobId = decodeURIComponent(jobDetailMatch[2]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const deleted = await deleteJob(jobId, projectId);
      if (!deleted) {
        return writeError(response, 404, "job not found", "JOB_NOT_FOUND");
      }
      publishProjectEvent(projectId, {
        type: "job_deleted",
        jobId
      });
      return json(response, 200, { ok: true, deletedJobId: jobId });
    }
    if (jobRetryMatch && method === "POST") {
      const projectId = decodeURIComponent(jobRetryMatch[1]);
      const jobId = decodeURIComponent(jobRetryMatch[2]);
      const project = await getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const job = await getJob(jobId, projectId);
      if (!job) {
        return writeError(response, 404, "job not found", "JOB_NOT_FOUND");
      }
      if (job.status !== "failed") {
        return writeError(response, 409, "only failed jobs can be retried", "JOB_RETRY_CONFLICT");
      }
      if (job.kind !== "clip" || !job.shotId) {
        return writeError(response, 400, "retry supported only for failed clip jobs", "JOB_RETRY_UNSUPPORTED");
      }
      const shot = await getShot(job.shotId, projectId);
      if (!shot) {
        return writeError(response, 404, "shot not found", "SHOT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const result = await queueShotGeneration({
        projectId,
        shot,
        userId: auth.userId,
        idempotencyKey: payload.idempotencyKey
      });
      return json(response, 200, {
        shot: result.queuedShot,
        job: result.job,
        quote: {
          sparksCost: result.quote.sparksCost,
          modelTier: result.quote.modelTier,
          modelId: result.quote.modelId,
          estimatedDurationSec: result.quote.estimatedDurationSec,
          idempotencyKey: result.generationIdempotencyKey
        }
      });
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
