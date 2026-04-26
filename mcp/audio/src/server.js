import { randomUUID } from "node:crypto";

const TOOLS = [
  "generate_dialogue",
  "generate_score",
  "lookup_sfx",
  "generate_sfx",
  "mix_scene",
  "lipsync"
];

function audioResult(kind, input = {}) {
  const id = randomUUID();
  return {
    id,
    kind,
    status: "ready",
    sourceUrl: `https://pubfuse.local/cinefuse/audio/${kind}/${id}.wav`,
    waveformUrl: `https://pubfuse.local/cinefuse/audio/${kind}/${id}.png`,
    durationMs: Number(input.durationMs ?? 4000),
    laneIndex: Number(input.laneIndex ?? 0),
    startMs: Number(input.startMs ?? 0),
    costToUsCents: Number(input.costToUsCents ?? 9),
    sparksCost: Number(input.sparksCost ?? 15)
  };
}

export function createServer() {
  return {
    name: "audio",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input = {}) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      if (tool === "lookup_sfx") {
        return {
          ok: true,
          server: "audio",
          tool,
          matches: [
            { id: "sfx-rain-light", label: "Light Rain Bed", category: "atmos" },
            { id: "sfx-door-metal", label: "Metal Door Slam", category: "impact" }
          ]
        };
      }

      const kindByTool = {
        generate_dialogue: "dialogue",
        generate_score: "score",
        generate_sfx: "sfx",
        mix_scene: "mix",
        lipsync: "lipsync"
      };
      return {
        ok: true,
        server: "audio",
        tool,
        track: audioResult(kindByTool[tool] ?? "audio", input)
      };
    }
  };
}
