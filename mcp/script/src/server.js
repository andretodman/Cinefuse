import { randomUUID } from "node:crypto";

const TOOLS = [
  "generate_beat_sheet",
  "revise_scene",
  "generate_shot_prompts",
  "extract_characters",
  "extract_dialogue",
  "revise_dialogue"
];

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function inferSceneCount(targetDurationMinutes) {
  const requested = Number(targetDurationMinutes ?? 5);
  if (!Number.isFinite(requested)) {
    return 8;
  }
  return clamp(Math.round(requested * 2), 8, 15);
}

function generateSceneTitle(index, tone) {
  const labels = ["Opening", "Setup", "Complication", "Escalation", "Twist", "Setback", "Climax", "Resolution"];
  const label = labels[index % labels.length];
  return `${label} ${index + 1} (${tone})`;
}

function createPrompt(sceneTitle, sequence) {
  return `${sceneTitle} shot ${sequence + 1} with cinematic framing and clear subject action`;
}

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

      if (tool === "generate_beat_sheet") {
        const tone = input?.tone ?? "drama";
        const logline = input?.logline ?? "Untitled story";
        const sceneCount = inferSceneCount(input?.targetDurationMinutes);
        const scenes = Array.from({ length: sceneCount }).map((_, index) => {
          const title = generateSceneTitle(index, tone);
          return {
            id: randomUUID(),
            orderIndex: index,
            title,
            description: `${title}. Story beat derived from: ${logline}`,
            mood: tone
          };
        });
        return {
          ok: true,
          server: "script",
          tool,
          scenes,
          summary: {
            sceneCount,
            tone,
            targetDurationMinutes: input?.targetDurationMinutes ?? 5
          }
        };
      }

      if (tool === "generate_shot_prompts") {
        const sceneTitle = input?.sceneTitle ?? "Scene";
        const prompts = Array.from({ length: 3 }).map((_, index) => ({
          id: randomUUID(),
          prompt: createPrompt(sceneTitle, index)
        }));
        return {
          ok: true,
          server: "script",
          tool,
          prompts
        };
      }

      if (tool === "revise_scene") {
        return {
          ok: true,
          server: "script",
          tool,
          scene: {
            id: input?.sceneId ?? randomUUID(),
            orderIndex: input?.orderIndex ?? 0,
            title: input?.title ?? "Revised Scene",
            description: input?.revision ?? input?.description ?? "",
            mood: input?.mood ?? "drama"
          }
        };
      }

      if (tool === "extract_characters") {
        const text = `${input?.logline ?? ""} ${input?.sceneDescription ?? ""}`;
        const matches = text.match(/\b[A-Z][a-z]{2,}\b/g) ?? [];
        const unique = Array.from(new Set(matches)).slice(0, 8);
        return {
          ok: true,
          server: "script",
          tool,
          characters: unique.map((name) => ({ id: randomUUID(), name }))
        };
      }

      if (tool === "extract_dialogue") {
        return {
          ok: true,
          server: "script",
          tool,
          dialogue: [
            { speaker: "Lead", line: "We don't have much time." },
            { speaker: "Partner", line: "Then let's move now." }
          ]
        };
      }

      if (tool === "revise_dialogue") {
        return {
          ok: true,
          server: "script",
          tool,
          dialogue: input?.dialogue ?? []
        };
      }

      return { ok: true, server: "script", tool, input: input ?? null };
    }
  };
}
