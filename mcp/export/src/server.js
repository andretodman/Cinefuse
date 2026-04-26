import { randomUUID } from "node:crypto";

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
    async invoke(tool, input = {}) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      const id = randomUUID();
      return {
        ok: true,
        server: "export",
        tool,
        export: {
          id,
          status: "ready",
          fileUrl: `https://pubfuse.local/cinefuse/exports/${id}.mp4`,
          archiveUrl: `https://pubfuse.local/cinefuse/exports/${id}.zip`,
          costToUsCents: Number(input.costToUsCents ?? 19),
          sparksCost: Number(input.sparksCost ?? 40)
        }
      };
    }
  };
}
