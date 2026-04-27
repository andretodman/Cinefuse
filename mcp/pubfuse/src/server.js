const TOOLS = [
  "get_user",
  "update_profile",
  "list_files",
  "upload_file",
  "get_file_url",
  "create_scheduled_event",
  "get_spark_balance",
  "verify_webhook_hmac"
];

function isTestMode() {
  return process.env.NODE_ENV === "test"
    || process.env.CINEFUSE_ALLOW_STUB_MEDIA === "true"
    || process.argv.includes("--test");
}

function resolveBaseUrl() {
  return process.env.CINEFUSE_PUBFUSE_API_BASE_URL ?? process.env.PUBFUSE_API_BASE_URL ?? "";
}

function normalizeBaseUrl(url) {
  return url.replace(/\/+$/, "");
}

function buildHeaders() {
  const apiKey = process.env.PUBFUSE_CLIENT_SECRET ?? process.env.PUBFUSE_API_KEY ?? "";
  return {
    "content-type": "application/json",
    ...(apiKey ? { authorization: `Bearer ${apiKey}` } : {})
  };
}

function ensureTool(tool) {
  if (!TOOLS.includes(tool)) {
    throw new Error(`Unknown tool: ${tool}`);
  }
}

function fallbackResponse(tool, input = {}) {
  if (tool === "upload_file") {
    const fileId = input.fileId ?? `file_${Math.random().toString(36).slice(2, 10)}`;
    const key = typeof input.key === "string" && input.key.length > 0 ? input.key : fileId;
    return {
      ok: true,
      server: "pubfuse",
      tool,
      fileId,
      fileUrl: `https://files.cinefuse.test/${key}`,
      input
    };
  }
  return {
    ok: true,
    server: "pubfuse",
    tool,
    input: input ?? null
  };
}

async function invokePubfuseApi(tool, input = {}) {
  const baseUrl = resolveBaseUrl();
  if (!baseUrl) {
    if (isTestMode()) {
      return fallbackResponse(tool, input);
    }
    throw new Error("Pubfuse MCP is not configured. Set PUBFUSE_API_BASE_URL (or CINEFUSE_PUBFUSE_API_BASE_URL).");
  }
  const response = await fetch(`${normalizeBaseUrl(baseUrl)}/api/v1/cinefuse/mcp/${tool}`, {
    method: "POST",
    headers: buildHeaders(),
    body: JSON.stringify(input),
    signal: AbortSignal.timeout(30_000)
  });
  if (!response.ok) {
    throw new Error(`pubfuse api error (${response.status}): ${await response.text()}`);
  }
  return response.json();
}

export function createServer() {
  return {
    name: "pubfuse",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      ensureTool(tool);
      const payload = await invokePubfuseApi(tool, input ?? {});
      return {
        ok: true,
        server: "pubfuse",
        tool,
        ...(payload && typeof payload === "object" ? payload : { result: payload }),
        input: input ?? null
      };
    }
  };
}
