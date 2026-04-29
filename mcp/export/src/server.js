import { randomUUID } from "node:crypto";

const TOOLS = [
  "encode_final",
  "encode_audio_mixdown",
  "upload_to_pubfuse",
  "publish_to_pubfuse_stream",
  "archive_project",
  "connect_youtube",
  "connect_vimeo"
];

export function createServer() {
  return {
    name: "export",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input = {}) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      const exported = await invokeExportTool(tool, input);
      return {
        ok: true,
        server: "export",
        tool,
        export: exported
      };
    }
  };
}

function isTestMode() {
  return process.env.NODE_ENV === "test"
    || process.env.CINEFUSE_ALLOW_STUB_MEDIA === "true"
    || process.argv.includes("--test");
}

// In non-test runs, encode_final / encode_audio_mixdown require CINEFUSE_EXPORT_PROVIDER_URL (no stub fallback).

function fallbackExport(tool, input = {}) {
  const id = randomUUID();
  const base = `https://files.cinefuse.test/exports/${id}`;
  if (tool === "encode_audio_mixdown") {
    return {
      id,
      status: "ready",
      fileUrl: `${base}.wav`,
      archiveUrl: null,
      costToUsCents: Number(input.costToUsCents ?? 12),
      sparksCost: Number(input.sparksCost ?? 18),
      publishTarget: null
    };
  }
  return {
    id,
    status: "ready",
    fileUrl: tool === "archive_project" ? `${base}.zip` : `${base}.mp4`,
    archiveUrl: `${base}.zip`,
    costToUsCents: Number(input.costToUsCents ?? 19),
    sparksCost: Number(input.sparksCost ?? 40),
    publishTarget: input.publishTarget ?? null
  };
}

function providerHeaders(token) {
  return {
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {})
  };
}

function normalizeExport(payload, tool, input = {}) {
  const id = payload?.id ?? randomUUID();
  const fileUrl = payload?.fileUrl ?? payload?.url ?? null;
  const archiveUrl = payload?.archiveUrl ?? (tool === "archive_project" ? fileUrl : null);
  if ((tool === "encode_final" || tool === "encode_audio_mixdown" || tool === "upload_to_pubfuse" || tool === "publish_to_pubfuse_stream")
    && (typeof fileUrl !== "string" || fileUrl.length === 0)) {
    throw new Error(`export provider returned no fileUrl for ${tool}`);
  }
  return {
    id,
    status: payload?.status ?? "ready",
    fileUrl: typeof fileUrl === "string" ? fileUrl : null,
    archiveUrl: typeof archiveUrl === "string" ? archiveUrl : null,
    costToUsCents: Number(payload?.costToUsCents ?? input.costToUsCents ?? 19),
    sparksCost: Number(payload?.sparksCost ?? input.sparksCost ?? 40),
    publishTarget: payload?.publishTarget ?? input.publishTarget ?? null,
    oauthUrl: payload?.oauthUrl ?? null
  };
}

async function invokeExportTool(tool, input = {}) {
  const providerUrl = process.env.CINEFUSE_EXPORT_PROVIDER_URL;
  if (!providerUrl) {
    if (isTestMode()) {
      return fallbackExport(tool, input);
    }
    throw new Error("Export pipeline is not configured. Set CINEFUSE_EXPORT_PROVIDER_URL.");
  }

  const response = await fetch(providerUrl, {
    method: "POST",
    headers: providerHeaders(process.env.CINEFUSE_EXPORT_PROVIDER_TOKEN ?? ""),
    body: JSON.stringify({ tool, input }),
    signal: AbortSignal.timeout(60_000)
  });
  if (!response.ok) {
    throw new Error(`export provider error (${response.status}): ${await response.text()}`);
  }
  const payload = await response.json();
  return normalizeExport(payload.export ?? payload.result ?? payload, tool, input);
}
