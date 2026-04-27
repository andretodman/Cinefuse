import { randomUUID } from "node:crypto";

const TOOLS = [
  "generate_dialogue",
  "generate_score",
  "lookup_sfx",
  "generate_sfx",
  "mix_scene",
  "lipsync"
];

function isTestMode() {
  return process.env.NODE_ENV === "test"
    || process.env.CINEFUSE_ALLOW_STUB_MEDIA === "true"
    || process.argv.includes("--test");
}

function fallbackTrack(kind, input = {}) {
  const id = randomUUID();
  return {
    id,
    kind,
    status: "ready",
    sourceUrl: `https://files.cinefuse.test/audio/${kind}/${id}.wav`,
    waveformUrl: `https://files.cinefuse.test/audio/${kind}/${id}.png`,
    durationMs: Number(input.durationMs ?? 4000),
    laneIndex: Number(input.laneIndex ?? 0),
    startMs: Number(input.startMs ?? 0),
    costToUsCents: Number(input.costToUsCents ?? 9),
    sparksCost: Number(input.sparksCost ?? 15)
  };
}

function resolveProviderUrl(tool) {
  const explicitByTool = {
    generate_dialogue: process.env.CINEFUSE_AUDIO_DIALOGUE_PROVIDER_URL,
    generate_score: process.env.CINEFUSE_AUDIO_SCORE_PROVIDER_URL,
    generate_sfx: process.env.CINEFUSE_AUDIO_SFX_PROVIDER_URL,
    mix_scene: process.env.CINEFUSE_AUDIO_MIX_PROVIDER_URL,
    lipsync: process.env.CINEFUSE_AUDIO_LIPSYNC_PROVIDER_URL
  };
  return explicitByTool[tool] ?? process.env.CINEFUSE_AUDIO_PROVIDER_URL ?? "";
}

function providerHeaders(token) {
  return {
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {})
  };
}

function normalizeTrack(rawTrack, kind, input = {}) {
  const id = typeof rawTrack?.id === "string" && rawTrack.id.length > 0 ? rawTrack.id : randomUUID();
  const sourceUrl = rawTrack?.sourceUrl ?? rawTrack?.url ?? null;
  if (typeof sourceUrl !== "string" || sourceUrl.length === 0) {
    throw new Error("audio provider returned no sourceUrl");
  }
  return {
    id,
    kind,
    status: rawTrack?.status ?? "ready",
    sourceUrl,
    waveformUrl: rawTrack?.waveformUrl ?? null,
    durationMs: Number(rawTrack?.durationMs ?? input.durationMs ?? 4000),
    laneIndex: Number(rawTrack?.laneIndex ?? input.laneIndex ?? 0),
    startMs: Number(rawTrack?.startMs ?? input.startMs ?? 0),
    costToUsCents: Number(rawTrack?.costToUsCents ?? input.costToUsCents ?? 9),
    sparksCost: Number(rawTrack?.sparksCost ?? input.sparksCost ?? 15)
  };
}

async function callAudioProvider(tool, kind, input = {}) {
  const url = resolveProviderUrl(tool);
  if (!url) {
    if (isTestMode()) {
      return fallbackTrack(kind, input);
    }
    throw new Error(
      "Audio generation is not configured. Set CINEFUSE_AUDIO_PROVIDER_URL or tool-specific CINEFUSE_AUDIO_*_PROVIDER_URL."
    );
  }
  const token = process.env.CINEFUSE_AUDIO_PROVIDER_TOKEN ?? "";
  const response = await fetch(url, {
    method: "POST",
    headers: providerHeaders(token),
    body: JSON.stringify({
      tool,
      kind,
      input
    }),
    signal: AbortSignal.timeout(30_000)
  });
  if (!response.ok) {
    throw new Error(`audio provider error (${response.status}): ${await response.text()}`);
  }
  const payload = await response.json();
  return normalizeTrack(payload.track ?? payload.audioTrack ?? payload, kind, input);
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
            {
              id: "freesound-rain-bed",
              label: "Rain Ambience Bed",
              category: "atmos",
              sourceUrl: "https://cdn.freesound.org/previews/648/648816_1547956-lq.mp3"
            },
            {
              id: "freesound-door-slam",
              label: "Heavy Metal Door Slam",
              category: "impact",
              sourceUrl: "https://cdn.freesound.org/previews/725/725423_4019024-lq.mp3"
            }
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
        track: await callAudioProvider(tool, kindByTool[tool] ?? "audio", input)
      };
    }
  };
}
