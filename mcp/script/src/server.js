const TOOLS = [
  "generate_beat_sheet",
  "revise_scene",
  "generate_shot_prompts",
  "extract_characters",
  "extract_dialogue",
  "revise_dialogue"
];

export function createServer() {
  return {
    name: "script",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      return { ok: true, server: "script", tool, input: input ?? null };
    }
  };
}
