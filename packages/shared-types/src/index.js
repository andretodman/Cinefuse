export const PROJECT_PHASES = [
  "script",
  "storyboard",
  "character",
  "clip",
  "audio",
  "stitch",
  "export",
  "done"
];

export function createProject(input) {
  return {
    id: input.id,
    ownerUserId: input.ownerUserId,
    title: input.title,
    logline: input.logline ?? "",
    targetDurationMinutes: input.targetDurationMinutes ?? 5,
    tone: input.tone ?? "drama",
    currentPhase: input.currentPhase ?? "script",
    createdAt: input.createdAt ?? new Date().toISOString(),
    updatedAt: input.updatedAt ?? new Date().toISOString()
  };
}

export function isValidProjectPhase(value) {
  return PROJECT_PHASES.includes(value);
}

export function createIdempotencyKey(parts) {
  return parts.join(":");
}
