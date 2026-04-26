const TOOLS = ["quote_clip", "generate_clip", "regenerate_clip", "list_models"];

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
      return { ok: true, server: "clip", tool, input: input ?? null };
    }
  };
}
