const TOOLS = [
  "create_character",
  "train_identity",
  "embed_identity",
  "list_characters",
  "delete_character",
  "preview_character"
];

export function createServer() {
  return {
    name: "character",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      return { ok: true, server: "character", tool, input: input ?? null };
    }
  };
}
