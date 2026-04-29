#!/usr/bin/env node
/**
 * Production/staging smoke: same endpoints as Mac APIClient.generateShot + listJobs/listTimeline.
 *
 * Env (required):
 *   CINEFUSE_VERIFY_BASE_URL   e.g. https://cinefuse.pubfuse.com
 *   CINEFUSE_VERIFY_BEARER     JWT or full "Bearer …"
 *   CINEFUSE_VERIFY_PROJECT_ID project UUID
 *
 * Optional:
 *   CINEFUSE_VERIFY_SHOT_ID    existing shot; if unset, creates a new shot (standard tier)
 *
 * Exit: 0 if shot reaches ready or failed (terminal); 1 on usage error or timeout.
 */

const PREFIX = "/api/v1/cinefuse";

function usage(msg) {
  if (msg) {
    console.error(msg);
  }
  console.error(
    "Usage: set CINEFUSE_VERIFY_BASE_URL, CINEFUSE_VERIFY_BEARER, CINEFUSE_VERIFY_PROJECT_ID " +
      "[CINEFUSE_VERIFY_SHOT_ID]"
  );
  process.exit(1);
}

function authHeader(raw) {
  const t = String(raw ?? "").trim();
  if (!t) return "";
  return t.toLowerCase().startsWith("bearer ") ? t : `Bearer ${t}`;
}

async function httpJson(method, base, path, { bearer, body } = {}) {
  const url = new URL(path, base.endsWith("/") ? base : `${base}/`);
  const headers = { accept: "application/json" };
  if (bearer) {
    headers.authorization = authHeader(bearer);
  }
  if (body !== undefined) {
    headers["content-type"] = "application/json";
  }
  const res = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(120_000)
  });
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { _raw: text };
  }
  return { status: res.status, json };
}

async function main() {
  const base = process.env.CINEFUSE_VERIFY_BASE_URL?.trim();
  const bearer = process.env.CINEFUSE_VERIFY_BEARER?.trim();
  const projectId = process.env.CINEFUSE_VERIFY_PROJECT_ID?.trim();
  let shotId = process.env.CINEFUSE_VERIFY_SHOT_ID?.trim();

  if (!base || !bearer || !projectId) {
    usage("Missing required env.");
  }

  const health = await httpJson("GET", base, `${PREFIX}/health`, { bearer });
  if (health.status !== 200) {
    console.error("health failed", health.status, health.json);
    process.exit(1);
  }
  console.log("health ok", health.json);

  if (!shotId) {
    const create = await httpJson("POST", base, `${PREFIX}/projects/${encodeURIComponent(projectId)}/shots`, {
      bearer,
      body: {
        prompt: "smoke instrumental one bar drums",
        modelTier: "standard"
      }
    });
    if (create.status !== 201) {
      console.error("create shot failed", create.status, create.json);
      process.exit(1);
    }
    shotId = create.json.shot?.id;
    if (!shotId) {
      console.error("no shot id in response", create.json);
      process.exit(1);
    }
    console.log("created shot", shotId);
  }

  const gen = await httpJson(
    "POST",
    base,
    `${PREFIX}/projects/${encodeURIComponent(projectId)}/shots/${encodeURIComponent(shotId)}/generate`,
    {
      bearer,
      body: { generationKind: "sound", soundBlueprintIds: [] }
    }
  );
  if (gen.status !== 200) {
    console.error("generate failed", gen.status, gen.json);
    process.exit(1);
  }
  console.log("generate accepted", { shotId, jobId: gen.json.job?.id, shotStatus: gen.json.shot?.status });

  const deadline = Date.now() + 240_000;
  let lastShot;
  let lastJob;
  while (Date.now() < deadline) {
    const shotsRes = await httpJson(
      "GET",
      base,
      `${PREFIX}/projects/${encodeURIComponent(projectId)}/shots`,
      { bearer }
    );
    const jobsRes = await httpJson(
      "GET",
      base,
      `${PREFIX}/projects/${encodeURIComponent(projectId)}/jobs`,
      { bearer }
    );
    if (shotsRes.status !== 200 || jobsRes.status !== 200) {
      console.error("poll failed", shotsRes.status, jobsRes.status);
      process.exit(1);
    }
    const shots = shotsRes.json.shots ?? [];
    const jobs = jobsRes.json.jobs ?? [];
    lastShot = shots.find((s) => s.id === shotId);
    lastJob = jobs.find((j) => j.shotId === shotId && j.kind === "audio");
    const st = lastShot?.status ?? "unknown";
    const jt = lastJob?.status ?? "unknown";
    console.log("poll", new Date().toISOString(), "shot=", st, "audioJob=", jt);
    if (st === "ready" || st === "failed") {
      console.log("terminal shot", JSON.stringify(lastShot, null, 2));
      console.log("audio job", JSON.stringify(lastJob, null, 2));
      process.exit(0);
    }
    await new Promise((r) => setTimeout(r, 1500));
  }

  console.error("timeout waiting for terminal shot status", { lastShot, lastJob });
  process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
