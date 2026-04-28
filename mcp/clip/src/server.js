const TOOLS = ["quote_clip", "generate_clip", "regenerate_clip", "list_models"];

const TIER_CONFIG = {
  budget: { sparks: 50, modelId: "wan-2.6", estimatedDurationSec: 5, costToUsCents: 35 },
  standard: { sparks: 70, modelId: "kling-2.5-turbo-pro", estimatedDurationSec: 5, costToUsCents: 52 },
  premium: { sparks: 250, modelId: "veo-3.1", estimatedDurationSec: 5, costToUsCents: 180 }
};

function resolveTierConfig(modelTier) {
  return TIER_CONFIG[modelTier] ?? TIER_CONFIG.budget;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function shouldRetryStatus(status) {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

function testModeClipUrl(input) {
  const identifier = input?.shotId ?? "clip";
  return `https://files.cinefuse.test/clips/${identifier}.mp4`;
}

function isTestMode() {
  return process.env.NODE_ENV === "test"
    || process.env.CINEFUSE_ALLOW_STUB_MEDIA === "true"
    || process.argv.includes("--test");
}

function normalizeModelEndpoint(value) {
  if (typeof value !== "string") {
    return "";
  }
  const trimmed = value.trim();
  return trimmed.replace(/^\/+/, "");
}

function resolveFalEndpointForTier(modelTier) {
  const endpointByTier = {
    budget: process.env.CINEFUSE_FAL_CLIP_MODEL_BUDGET,
    standard: process.env.CINEFUSE_FAL_CLIP_MODEL_STANDARD,
    premium: process.env.CINEFUSE_FAL_CLIP_MODEL_PREMIUM
  };
  return normalizeModelEndpoint(endpointByTier[modelTier] ?? endpointByTier.budget ?? "");
}

function extractClipUrl(payload) {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const candidates = [
    payload.clipUrl,
    payload.videoUrl,
    payload.url,
    payload.output?.video?.url,
    payload.output?.url,
    payload.video?.url,
    Array.isArray(payload.output) ? payload.output[0]?.url : null,
    Array.isArray(payload.videos) ? payload.videos[0]?.url : null
  ];
  return candidates.find((candidate) => typeof candidate === "string" && candidate.trim().length > 0) ?? null;
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let payload = null;
  if (text.length > 0) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = null;
    }
  }
  return { response, payload, text };
}

function uniqueNonEmptyStrings(values) {
  const seen = new Set();
  const ordered = [];
  for (const value of values) {
    if (typeof value !== "string") {
      continue;
    }
    const trimmed = value.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    ordered.push(trimmed);
  }
  return ordered;
}

function clipText(value, maxLength = 220) {
  if (typeof value !== "string") {
    return "";
  }
  const normalized = value.trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, maxLength)}…`;
}

function withFalContext(message, context) {
  return `${message} fal_context=${JSON.stringify(context)}`;
}

function buildFalStatusUrls({ submitBody, endpoint, requestId }) {
  const endpointBase = `https://queue.fal.run/${endpoint}/requests/${requestId}`;
  return uniqueNonEmptyStrings([
    submitBody?.status_url,
    submitBody?.statusUrl,
    submitBody?.urls?.status,
    `${endpointBase}/status`,
    endpointBase
  ]);
}

async function generateViaFal({ input, config, modelTier }) {
  const falApiKey = process.env.FAL_API_KEY;
  if (!falApiKey) {
    return null;
  }

  const endpoint = resolveFalEndpointForTier(modelTier);
  if (!endpoint) {
    throw new Error(
      `FAL model endpoint for tier "${modelTier}" is not configured. Set CINEFUSE_FAL_CLIP_MODEL_${modelTier.toUpperCase()}.`
    );
  }

  const submitUrl = `https://queue.fal.run/${endpoint}`;
  const headers = {
    authorization: `Key ${falApiKey}`,
    "content-type": "application/json"
  };
  const submitPayload = {
    prompt: input?.prompt ?? "",
    duration: Number(input?.durationSec ?? config.estimatedDurationSec),
    modelTier,
    shotId: input?.shotId ?? null,
    projectId: input?.projectId ?? null
  };

  const { response: submitResponse, payload: submitBody, text: submitText } = await fetchJson(submitUrl, {
    method: "POST",
    headers,
    body: JSON.stringify(submitPayload),
    signal: AbortSignal.timeout(30_000)
  });
  if (!submitResponse.ok) {
    throw new Error(`fal submit failed (${submitResponse.status}): ${submitText}`);
  }
  console.info("[clip] fal submit accepted", {
    shotId: input?.shotId ?? null,
    projectId: input?.projectId ?? null,
    modelTier,
    endpoint
  });

  const submitClipUrl = extractClipUrl(submitBody);
  if (submitClipUrl) {
    return {
      modelId: submitBody?.modelId ?? config.modelId,
      sparksCost: submitBody?.sparksCost ?? config.sparks,
      estimatedDurationSec: submitBody?.estimatedDurationSec ?? config.estimatedDurationSec,
      costToUsCents: Number(submitBody?.costToUsCents ?? config.costToUsCents),
      status: "ready",
      clipUrl: submitClipUrl,
      thumbnailUrl: submitBody?.thumbnailUrl ?? null
    };
  }

  const requestId = submitBody?.request_id ?? submitBody?.requestId ?? submitBody?.id;
  if (typeof requestId !== "string" || requestId.length === 0) {
    throw new Error(withFalContext("fal submit response missing request id", {
      endpoint,
      statusCode: submitResponse.status,
      submitUrl,
      responseSnippet: clipText(submitText)
    }));
  }
  const statusUrls = buildFalStatusUrls({ submitBody, endpoint, requestId });
  if (statusUrls.length === 0) {
    throw new Error(withFalContext("fal submit response missing status url", {
      endpoint,
      requestId,
      submitUrl,
      statusCode: submitResponse.status
    }));
  }
  console.info("[clip] fal request created", {
    requestId,
    shotId: input?.shotId ?? null,
    projectId: input?.projectId ?? null,
    modelTier,
    endpoint,
    statusUrls
  });

  const maxPollAttempts = Number(process.env.CINEFUSE_FAL_MAX_POLL_ATTEMPTS ?? 60);
  const pollDelayMs = Number(process.env.CINEFUSE_FAL_POLL_DELAY_MS ?? 2000);
  let activeStatusUrl = statusUrls[0];
  for (let attempt = 1; attempt <= maxPollAttempts; attempt += 1) {
    await sleep(pollDelayMs);
    let statusBody = null;
    let statusText = "";
    let retryableStatusFailure = null;
    let terminalFailure = null;
    let resolvedStatusUrl = activeStatusUrl;
    for (const statusUrl of statusUrls) {
      const { response: statusResponse, payload, text } = await fetchJson(statusUrl, {
        method: "GET",
        headers,
        signal: AbortSignal.timeout(20_000)
      });
      if (statusResponse.ok) {
        statusBody = payload;
        statusText = text;
        resolvedStatusUrl = statusUrl;
        break;
      }
      if (statusResponse.status === 405) {
        terminalFailure = {
          statusCode: statusResponse.status,
          statusUrl,
          responseSnippet: clipText(text)
        };
        continue;
      }
      if (shouldRetryStatus(statusResponse.status)) {
        retryableStatusFailure = {
          statusCode: statusResponse.status,
          statusUrl,
          responseSnippet: clipText(text)
        };
        break;
      }
      throw new Error(withFalContext(`fal status failed (${statusResponse.status}): ${text}`, {
        endpoint,
        requestId,
        attempt,
        statusCode: statusResponse.status,
        statusUrl,
        responseSnippet: clipText(text)
      }));
    }
    if (!statusBody) {
      if (retryableStatusFailure && attempt < maxPollAttempts) {
        continue;
      }
      if (retryableStatusFailure) {
        throw new Error(withFalContext(
          `fal status failed (${retryableStatusFailure.statusCode}): ${retryableStatusFailure.responseSnippet}`,
          {
            endpoint,
            requestId,
            attempt,
            statusCode: retryableStatusFailure.statusCode,
            statusUrl: retryableStatusFailure.statusUrl,
            responseSnippet: retryableStatusFailure.responseSnippet
          }
        ));
      }
      if (terminalFailure) {
        throw new Error(withFalContext(
          `fal status failed (${terminalFailure.statusCode}): ${terminalFailure.responseSnippet}`,
          {
            endpoint,
            requestId,
            attempt,
            statusCode: terminalFailure.statusCode,
            statusUrl: terminalFailure.statusUrl,
            statusUrlCandidates: statusUrls,
            responseSnippet: terminalFailure.responseSnippet
          }
        ));
      }
      continue;
    }
    activeStatusUrl = resolvedStatusUrl;

    const rawStatus = statusBody?.status ?? statusBody?.state ?? "";
    const normalizedStatus = String(rawStatus).toLowerCase();
    if (attempt === 1 || attempt % 5 === 0 || normalizedStatus === "completed") {
      console.info("[clip] fal poll", {
        requestId,
        endpoint,
        statusUrl: activeStatusUrl,
        attempt,
        maxPollAttempts,
        status: normalizedStatus || "unknown"
      });
    }
    if (normalizedStatus === "failed" || normalizedStatus === "error" || normalizedStatus === "canceled") {
      throw new Error(withFalContext(
        `fal generation failed: ${statusBody?.error ?? statusBody?.message ?? "provider error"}`,
        {
          endpoint,
          requestId,
          attempt,
          statusUrl: activeStatusUrl
        }
      ));
    }

    if (normalizedStatus === "completed" || normalizedStatus === "succeeded" || normalizedStatus === "done") {
      let responseBody = statusBody?.response ?? statusBody?.result ?? statusBody?.output ?? null;
      if (!responseBody && typeof statusBody?.response_url === "string") {
        const responseData = await fetchJson(statusBody.response_url, {
          method: "GET",
          headers,
          signal: AbortSignal.timeout(20_000)
        });
        if (!responseData.response.ok) {
          throw new Error(withFalContext(
            `fal response fetch failed (${responseData.response.status}): ${responseData.text}`,
            {
              endpoint,
              requestId,
              attempt,
              statusUrl: activeStatusUrl,
              responseUrl: statusBody.response_url,
              statusCode: responseData.response.status
            }
          ));
        }
        responseBody = responseData.payload;
      }

      const clipUrl = extractClipUrl(responseBody) ?? extractClipUrl(statusBody);
      if (!clipUrl) {
        throw new Error("fal completed but returned no clip URL");
      }
      return {
        modelId: responseBody?.modelId ?? statusBody?.modelId ?? config.modelId,
        sparksCost: responseBody?.sparksCost ?? config.sparks,
        estimatedDurationSec: responseBody?.estimatedDurationSec ?? config.estimatedDurationSec,
        costToUsCents: Number(responseBody?.costToUsCents ?? config.costToUsCents),
        status: "ready",
        requestId,
        falEndpoint: endpoint,
        falStatusUrl: activeStatusUrl,
        clipUrl,
        thumbnailUrl: responseBody?.thumbnailUrl ?? null
      };
    }
  }

  console.error("[clip] fal poll timeout", {
    requestId,
    endpoint,
    statusUrl: activeStatusUrl,
    maxPollAttempts
  });
  throw new Error(withFalContext(`fal generation timed out after ${maxPollAttempts} polls`, {
    endpoint,
    requestId,
    statusUrl: activeStatusUrl,
    maxPollAttempts
  }));
}

async function generateViaProvider({ input, config, modelTier }) {
  const providerUrl = process.env.CINEFUSE_CLIP_PROVIDER_URL;
  if (!providerUrl) {
    const falResult = await generateViaFal({ input, config, modelTier });
    if (falResult) {
      return falResult;
    }
    if (isTestMode()) {
      return {
        modelId: config.modelId,
        sparksCost: config.sparks,
        estimatedDurationSec: config.estimatedDurationSec,
        costToUsCents: config.costToUsCents,
        status: "ready",
        clipUrl: testModeClipUrl(input),
        thumbnailUrl: null
      };
    }
    throw new Error(
      "Clip generation is not configured. Set CINEFUSE_CLIP_PROVIDER_URL or FAL_API_KEY with CINEFUSE_FAL_CLIP_MODEL_*."
    );
  }

  const maxAttempts = 4;
  let attempt = 0;
  let delayMs = 500;
  let lastFailure = "unknown clip provider failure";
  while (attempt < maxAttempts) {
    attempt += 1;
    try {
      const response = await fetch(providerUrl, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: process.env.CINEFUSE_CLIP_PROVIDER_TOKEN
            ? `Bearer ${process.env.CINEFUSE_CLIP_PROVIDER_TOKEN}`
            : ""
        },
        body: JSON.stringify({
          prompt: input?.prompt ?? "",
          modelTier,
          modelId: config.modelId,
          shotId: input?.shotId ?? null,
          projectId: input?.projectId ?? null,
          userId: input?.userId ?? null
        }),
        signal: AbortSignal.timeout(20_000)
      });

      if (response.ok) {
        const payload = await response.json();
        const clipUrl = extractClipUrl(payload);
        if (!clipUrl) {
          throw new Error("clip provider returned success without clip URL");
        }
        return {
          modelId: payload.modelId ?? config.modelId,
          sparksCost: payload.sparksCost ?? config.sparks,
          estimatedDurationSec: payload.estimatedDurationSec ?? config.estimatedDurationSec,
          costToUsCents: payload.costToUsCents ?? config.costToUsCents,
          status: payload.status ?? "ready",
          clipUrl,
          thumbnailUrl: payload.thumbnailUrl ?? null
        };
      }

      const detail = await response.text();
      lastFailure = `clip provider error (${response.status}): ${detail}`;
      if (shouldRetryStatus(response.status) && attempt < maxAttempts) {
        await sleep(delayMs);
        delayMs *= 2;
        continue;
      }
      throw new Error(lastFailure);
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown provider network failure";
      lastFailure = message;
      if (attempt < maxAttempts) {
        await sleep(delayMs);
        delayMs *= 2;
        continue;
      }
      break;
    }
  }

  throw new Error(`clip generation failed after ${maxAttempts} attempts: ${lastFailure}`);
}

export function createServer() {
  return {
    name: "clip",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      if (tool === "list_models") {
        return {
          ok: true,
          server: "clip",
          tool,
          models: Object.entries(TIER_CONFIG).map(([tier, config]) => ({
            tier,
            modelId: config.modelId,
            estimatedDurationSec: config.estimatedDurationSec,
            sparks: config.sparks
          }))
        };
      }

      if (tool === "quote_clip") {
        const modelTier = input?.modelTier ?? "budget";
        const config = resolveTierConfig(modelTier);
        return {
          ok: true,
          server: "clip",
          tool,
          modelTier,
          modelId: config.modelId,
          sparksCost: config.sparks,
          estimatedDurationSec: config.estimatedDurationSec,
          input: input ?? null
        };
      }

      if (tool === "generate_clip" || tool === "regenerate_clip") {
        const modelTier = input?.modelTier ?? "budget";
        const config = resolveTierConfig(modelTier);
        const generation = await generateViaProvider({ input, config, modelTier });
        return {
          ok: true,
          server: "clip",
          tool,
          modelTier,
          modelId: generation.modelId,
          sparksCost: generation.sparksCost,
          estimatedDurationSec: generation.estimatedDurationSec,
          costToUsCents: generation.costToUsCents,
          status: generation.status,
          requestId: generation.requestId ?? null,
          falEndpoint: generation.falEndpoint ?? null,
          falStatusUrl: generation.falStatusUrl ?? null,
          clipUrl: generation.clipUrl,
          thumbnailUrl: generation.thumbnailUrl ?? null,
          input: input ?? null
        };
      }

      return { ok: true, server: "clip", tool, input: input ?? null };
    }
  };
}
