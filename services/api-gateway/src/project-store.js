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

export function deleteProject(projectId, ownerUserId) {
  const project = getProject(projectId, ownerUserId);
  if (!project) {
    return false;
  }
  projects.delete(projectId);
  for (const [shotId, shot] of shots.entries()) {
    if (shot.projectId === projectId) {
      shots.delete(shotId);
    }
  }
  for (const [jobId, job] of jobs.entries()) {
    if (job.projectId === projectId) {
      jobs.delete(jobId);
    }
  }
  return true;
}

export function listShots(projectId) {
  return Array.from(shots.values()).filter((shot) => shot.projectId === projectId);
}

export function saveShot(input) {
  const existing = shots.get(input.id);
  const now = new Date().toISOString();
  const shot = {
    id: input.id,
    projectId: input.projectId,
    prompt: input.prompt ?? existing?.prompt ?? "",
    modelTier: input.modelTier ?? existing?.modelTier ?? "budget",
    status: input.status ?? existing?.status ?? "draft",
    clipUrl: input.clipUrl ?? existing?.clipUrl ?? null,
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  shots.set(shot.id, shot);
  return shot;
}

export function getShot(shotId, projectId) {
  const shot = shots.get(shotId) ?? null;
  if (!shot) {
    return null;
  }
  if (projectId && shot.projectId !== projectId) {
    return null;
  }
  return shot;
}

export function listJobs(projectId) {
  return Array.from(jobs.values()).filter((job) => job.projectId === projectId);
}

export function saveJob(input) {
  const existing = jobs.get(input.id);
  const now = new Date().toISOString();
  const job = {
    id: input.id,
    projectId: input.projectId ?? existing?.projectId,
    shotId: input.shotId ?? existing?.shotId ?? null,
    kind: input.kind ?? existing?.kind ?? "clip",
    status: input.status ?? existing?.status ?? "queued",
    inputPayload: input.inputPayload ?? existing?.inputPayload ?? {},
    outputPayload: input.outputPayload ?? existing?.outputPayload ?? {},
    costToUsCents: input.costToUsCents ?? existing?.costToUsCents ?? 0,
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
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
