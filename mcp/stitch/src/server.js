import { randomUUID } from "node:crypto";

const TOOLS = [
  "preview_stitch",
  "final_stitch",
  "apply_transitions",
  "color_match",
  "bake_captions",
  "loudness_normalize"
];

function isTestMode() {
  return process.env.NODE_ENV === "test"
    || process.env.CINEFUSE_ALLOW_STUB_MEDIA === "true"
    || process.argv.includes("--test");
}

function fallbackStitch(kind, input = {}) {
  const id = randomUUID();
  return {
    id,
    kind,
    status: "ready",
    stitchedUrl: `https://files.cinefuse.test/stitch/${id}.mp4`,
    durationSec: Number(input.durationSec ?? 45),
    costToUsCents: Number(input.costToUsCents ?? 24)
  };
}

function providerHeaders(token) {
  return {
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {})
  };
}

function normalizeResult(payload, kind, input = {}) {
  const stitchedUrl = payload?.stitchedUrl ?? payload?.fileUrl ?? payload?.url ?? null;
  if (typeof stitchedUrl !== "string" || stitchedUrl.length === 0) {
    throw new Error("stitch provider returned no stitchedUrl");
  }
  return {
    id: payload?.id ?? randomUUID(),
    kind,
    status: payload?.status ?? "ready",
    stitchedUrl,
    durationSec: Number(payload?.durationSec ?? input.durationSec ?? 45),
    costToUsCents: Number(payload?.costToUsCents ?? input.costToUsCents ?? 24)
  };
}

async function callStitchProvider(tool, input = {}) {
  const providerUrl = process.env.CINEFUSE_STITCH_PROVIDER_URL;
  if (!providerUrl) {
    if (isTestMode()) {
      return fallbackStitch(tool, input);
    }
    throw new Error("Stitch pipeline is not configured. Set CINEFUSE_STITCH_PROVIDER_URL.");
  }
  const response = await fetch(providerUrl, {
    method: "POST",
    headers: providerHeaders(process.env.CINEFUSE_STITCH_PROVIDER_TOKEN ?? ""),
    body: JSON.stringify({ tool, input }),
    signal: AbortSignal.timeout(60_000)
  });
  if (!response.ok) {
    throw new Error(`stitch provider error (${response.status}): ${await response.text()}`);
  }
  const payload = await response.json();
  return normalizeResult(payload.result ?? payload.stitch ?? payload, tool, input);
}

export function createServer() {
  return {
    name: "stitch",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input = {}) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      return {
        ok: true,
        server: "stitch",
        tool,
        result: await callStitchProvider(tool, input),
        input
      };
    }
  };
}
