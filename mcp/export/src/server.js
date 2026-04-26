const TOOLS = [
  "encode_final",
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
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      return { ok: true, server: "export", tool, input: input ?? null };
    }
  };
}
