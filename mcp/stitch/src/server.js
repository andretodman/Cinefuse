import { randomUUID } from "node:crypto";

const TOOLS = [
  "preview_stitch",
  "final_stitch",
  "apply_transitions",
  "color_match",
  "bake_captions",
  "loudness_normalize"
];

function stitchedResult(kind) {
  const id = randomUUID();
  return {
    id,
    kind,
    status: "ready",
    stitchedUrl: `https://pubfuse.local/cinefuse/stitch/${id}.mp4`,
    durationSec: 45,
    costToUsCents: 24
  };
}

export function createServer() {
  return {
    name: "stitch",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input = {}) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      return {
        ok: true,
        server: "stitch",
        tool,
        result: stitchedResult(tool),
        input
      };
    }
  };
}
