const TOOLS = [
  "preview_stitch",
  "final_stitch",
  "apply_transitions",
  "color_match",
  "bake_captions",
  "loudness_normalize"
];

export function createServer() {
  return {
    name: "stitch",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      return { ok: true, server: "stitch", tool, input: input ?? null };
    }
  };
}
