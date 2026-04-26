import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { parseBearerAuth } from "./auth.js";
import { createMcpHost } from "./mcp-host.js";
import {
  getProject,
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

    if (method === "GET" && url.pathname === "/v1/sparks/balance") {
      const result = await mcpHost.invoke("billing", "get_balance", { userId: auth.userId });
      return json(response, 200, {
        userId: auth.userId,
        balance: result.balance
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

    const shotsMatch = url.pathname.match(/^\/api\/v1\/cinefuse\/projects\/([^/]+)\/shots$/);
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
