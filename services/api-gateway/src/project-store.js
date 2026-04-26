import { createProject } from "../../../packages/shared-types/src/index.js";

const projects = new Map();
const shots = new Map();
const jobs = new Map();

export function listProjects(ownerUserId) {
  return Array.from(projects.values()).filter((project) => project.ownerUserId === ownerUserId);
}

export function getProject(projectId, ownerUserId) {
  const project = projects.get(projectId) ?? null;
  if (!project) {
    return null;
  }
  if (project.ownerUserId !== ownerUserId) {
    return null;
  }
  return project;
}

export function saveProject(input) {
  const now = new Date().toISOString();
  const project = createProject({
    ...input,
    createdAt: input.createdAt ?? now,
    updatedAt: now
  });
  projects.set(project.id, project);
  return project;
}

export function listShots(projectId) {
  return Array.from(shots.values()).filter((shot) => shot.projectId === projectId);
}

export function saveShot(input) {
  const now = new Date().toISOString();
  const shot = {
    id: input.id,
    projectId: input.projectId,
    prompt: input.prompt ?? "",
    modelTier: input.modelTier ?? "budget",
    status: input.status ?? "draft",
    clipUrl: input.clipUrl ?? null,
    createdAt: input.createdAt ?? now,
    updatedAt: now
  };
  shots.set(shot.id, shot);
  return shot;
}

export function listJobs(projectId) {
  return Array.from(jobs.values()).filter((job) => job.projectId === projectId);
}

export function saveJob(input) {
  const now = new Date().toISOString();
  const job = {
    id: input.id,
    projectId: input.projectId,
    shotId: input.shotId ?? null,
    kind: input.kind ?? "clip",
    status: input.status ?? "queued",
    inputPayload: input.inputPayload ?? {},
    outputPayload: input.outputPayload ?? {},
    costToUsCents: input.costToUsCents ?? 0,
    createdAt: input.createdAt ?? now,
    updatedAt: now
  };
  jobs.set(job.id, job);
  return job;
}

export function clearProjects() {
  projects.clear();
  shots.clear();
  jobs.clear();
}
