import { randomUUID } from "node:crypto";
import { createHash } from "node:crypto";

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
  return `${sceneTitle} shot ${sequence + 1}: cinematic framing, clear subject action, concrete camera movement`;
}

function stableId(parts) {
  const hash = createHash("sha256").update(parts.join("|")).digest("hex").slice(0, 16);
  return `scn_${hash}`;
}

function sanitizeText(value, fallback) {
  if (typeof value !== "string") {
    return fallback;
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length > 0 ? normalized : fallback;
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
        const tone = sanitizeText(input?.tone, "drama").toLowerCase();
        const logline = sanitizeText(input?.logline, "Untitled story");
        const sceneCount = inferSceneCount(input?.targetDurationMinutes);
        const scenes = Array.from({ length: sceneCount }).map((_, index) => {
          const title = generateSceneTitle(index, tone);
          const description = `${title}. Story beat derived from: ${logline}`;
          return {
            id: stableId([logline, tone, String(sceneCount), String(index)]),
            orderIndex: index,
            title,
            description,
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
        const sceneTitle = sanitizeText(input?.sceneTitle, "Scene");
        const shotCount = clamp(Number(input?.shotCount ?? 3), 3, 6);
        const prompts = Array.from({ length: shotCount }).map((_, index) => ({
          id: stableId([sceneTitle, "prompt", String(index)]),
          prompt: createPrompt(sceneTitle, index),
          camera: index % 2 === 0 ? "wide" : "close",
          movement: index % 2 === 0 ? "dolly-in" : "pan-left"
        }));
        return {
          ok: true,
          server: "script",
          tool,
          prompts
        };
      }

      if (tool === "revise_scene") {
        const title = sanitizeText(input?.title, "Revised Scene");
        const revision = sanitizeText(input?.revision ?? input?.description, "No revision provided");
        const mood = sanitizeText(input?.mood, "drama").toLowerCase();
        return {
          ok: true,
          server: "script",
          tool,
          scene: {
            id: input?.sceneId ?? stableId([title, revision, mood]),
            orderIndex: clamp(Number(input?.orderIndex ?? 0), 0, 99),
            title,
            description: revision,
            mood
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
