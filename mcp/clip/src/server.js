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

function fallbackClipUrl(input) {
  const identifier = input?.shotId ?? "clip";
  return `https://pubfuse.local/cinefuse/clips/${identifier}.mp4`;
}

async function generateViaProvider({ input, config, modelTier }) {
  const providerUrl = process.env.CINEFUSE_CLIP_PROVIDER_URL;
  if (!providerUrl) {
    return {
      modelId: config.modelId,
      sparksCost: config.sparks,
      estimatedDurationSec: config.estimatedDurationSec,
      costToUsCents: config.costToUsCents,
      status: "ready",
      clipUrl: fallbackClipUrl(input)
    };
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
        return {
          modelId: payload.modelId ?? config.modelId,
          sparksCost: payload.sparksCost ?? config.sparks,
          estimatedDurationSec: payload.estimatedDurationSec ?? config.estimatedDurationSec,
          costToUsCents: payload.costToUsCents ?? config.costToUsCents,
          status: payload.status ?? "ready",
          clipUrl: payload.clipUrl ?? fallbackClipUrl(input)
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
          clipUrl: generation.clipUrl,
          input: input ?? null
        };
      }

      return { ok: true, server: "clip", tool, input: input ?? null };
    }
  };
}
