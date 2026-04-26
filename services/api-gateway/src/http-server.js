import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { parseBearerAuth } from "./auth.js";
import { createMcpHost } from "./mcp-host.js";
import {
  deleteProject,
  getProject,
  getShot,
  listJobs,
  listProjects,
  listShots,
  saveJob,
  saveProject,
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

  return createServer(async (request, response) => {
    const method = request.method ?? "GET";
    const url = new URL(request.url ?? "/", "http://localhost");

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
        projects: listProjects(auth.userId)
      });
    }

    if (
      method === "POST"
      && (url.pathname === "/api/v1/cinefuse/projects" || url.pathname === "/v1/projects")
    ) {
      applyLegacyProjectsAliasHeaders(response, url.pathname);
      const payload = await readBody(request);
      const project = saveProject({
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
      const project = getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { project });
    }
    if (projectDetailMatch && method === "DELETE") {
      const projectId = decodeURIComponent(projectDetailMatch[1]);
      const deleted = deleteProject(projectId, auth.userId);
      if (!deleted) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { ok: true, deletedProjectId: projectId });
    }

    const shotsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots$/);
    const shotQuoteMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots\/quote$/);
    if (shotQuoteMatch && method === "POST") {
      const projectId = decodeURIComponent(shotQuoteMatch[1]);
      const project = getProject(projectId, auth.userId);
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
      const project = getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { shots: listShots(projectId) });
    }
    if (shotsMatch && method === "POST") {
      const projectId = decodeURIComponent(shotsMatch[1]);
      const project = getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const shot = saveShot({
        id: payload.id ?? randomUUID(),
        projectId,
        prompt: payload.prompt ?? "",
        modelTier: payload.modelTier ?? "budget",
        status: payload.status ?? "draft",
        clipUrl: payload.clipUrl ?? null
      });
      return json(response, 201, { shot });
    }

    const shotGenerateMatch = url.pathname.match(
      /^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots\/([^/]+)\/generate$/
    );
    if (shotGenerateMatch && method === "POST") {
      const projectId = decodeURIComponent(shotGenerateMatch[1]);
      const shotId = decodeURIComponent(shotGenerateMatch[2]);
      const project = getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const shot = getShot(shotId, projectId);
      if (!shot) {
        return writeError(response, 404, "shot not found", "SHOT_NOT_FOUND");
      }

      const quote = await mcpHost.invoke("clip", "quote_clip", {
        shotId,
        projectId,
        prompt: shot.prompt,
        modelTier: shot.modelTier,
        userId: auth.userId
      });

      await mcpHost.invoke("billing", "debit", {
        userId: auth.userId,
        amount: quote.sparksCost,
        idempotencyKey: `shot-generate:${shotId}`,
        relatedResourceType: "shot",
        relatedResourceId: shotId
      });

      const generation = await mcpHost.invoke("clip", "generate_clip", {
        shotId,
        projectId,
        prompt: shot.prompt,
        modelTier: shot.modelTier,
        userId: auth.userId
      });

      const updatedShot = saveShot({
        ...shot,
        status: generation.status ?? "ready",
        clipUrl: generation.clipUrl ?? null
      });

      const job = saveJob({
        id: randomUUID(),
        projectId,
        shotId: updatedShot.id,
        kind: "clip",
        status: "done",
        inputPayload: {
          prompt: updatedShot.prompt,
          modelTier: updatedShot.modelTier
        },
        outputPayload: {
          modelId: generation.modelId ?? null,
          clipUrl: generation.clipUrl ?? null,
          sparksCost: quote.sparksCost
        },
        costToUsCents: generation.costToUsCents ?? 0
      });

      return json(response, 200, {
        shot: updatedShot,
        job,
        quote: {
          sparksCost: quote.sparksCost,
          modelTier: quote.modelTier,
          modelId: quote.modelId,
          estimatedDurationSec: quote.estimatedDurationSec
        }
      });
    }

    const jobsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/jobs$/);
    if (jobsMatch && method === "GET") {
      const projectId = decodeURIComponent(jobsMatch[1]);
      const project = getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      return json(response, 200, { jobs: listJobs(projectId) });
    }
    if (jobsMatch && method === "POST") {
      const projectId = decodeURIComponent(jobsMatch[1]);
      const project = getProject(projectId, auth.userId);
      if (!project) {
        return writeError(response, 404, "project not found", "PROJECT_NOT_FOUND");
      }
      const payload = await readBody(request);
      const job = saveJob({
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
  });
}
