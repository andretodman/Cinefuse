const TOOLS = ["quote_clip", "generate_clip", "regenerate_clip", "list_models"];

const TIER_CONFIG = {
  budget: { sparks: 50, modelId: "wan-2.6", estimatedDurationSec: 5, costToUsCents: 35 },
  standard: { sparks: 70, modelId: "kling-2.5-turbo-pro", estimatedDurationSec: 5, costToUsCents: 52 },
  premium: { sparks: 250, modelId: "veo-3.1", estimatedDurationSec: 5, costToUsCents: 180 }
};

function resolveTierConfig(modelTier) {
  return TIER_CONFIG[modelTier] ?? TIER_CONFIG.budget;
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
        const clipId = input?.shotId ?? "clip";
        return {
          ok: true,
          server: "clip",
          tool,
          modelTier,
          modelId: config.modelId,
          sparksCost: config.sparks,
          estimatedDurationSec: config.estimatedDurationSec,
          costToUsCents: config.costToUsCents,
          status: "ready",
          clipUrl: `https://pubfuse.local/cinefuse/clips/${clipId}.mp4`,
          input: input ?? null
        };
      }

      return { ok: true, server: "clip", tool, input: input ?? null };
    }
  };
}
