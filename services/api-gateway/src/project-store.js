import { createProject } from "../../../packages/shared-types/src/index.js";
import { Pool } from "pg";

const projects = new Map();
const scenes = new Map();
const characters = new Map();
const shots = new Map();
const jobs = new Map();

let pool;

function getPool() {
  const connectionString = process.env.CINEFUSE_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    return null;
  }
  if (!pool) {
    pool = new Pool({ connectionString });
  }
  return pool;
}

function mapProjectRow(row) {
  return {
    id: row.id,
    ownerUserId: row.owner_user_id,
    title: row.title,
    logline: row.logline,
    targetDurationMinutes: row.target_duration_minutes,
    tone: row.tone,
    currentPhase: row.current_phase,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapShotRow(row) {
  return {
    id: row.id,
    projectId: row.project_id,
    prompt: row.prompt,
    modelTier: row.model_tier,
    status: row.status,
    clipUrl: row.clip_url,
    characterLocks: row.character_locks ?? [],
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapSceneRow(row) {
  return {
    id: row.id,
    projectId: row.project_id,
    orderIndex: row.order_index,
    title: row.title,
    description: row.description,
    mood: row.mood,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapJobRow(row) {
  return {
    id: row.id,
    projectId: row.project_id,
    shotId: row.shot_id,
    kind: row.kind,
    status: row.status,
    inputPayload: row.input_payload ?? {},
    outputPayload: row.output_payload ?? {},
    costToUsCents: row.cost_to_us_cents ?? 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapCharacterRow(row) {
  return {
    id: row.id,
    projectId: row.project_id,
    name: row.name,
    description: row.description,
    status: row.status,
    previewUrl: row.preview_url,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export async function listProjects(ownerUserId) {
  const db = getPool();
  if (!db) {
    return Array.from(projects.values()).filter((project) => project.ownerUserId === ownerUserId);
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_projects
     WHERE owner_user_id = $1
     ORDER BY created_at DESC`,
    [ownerUserId]
  );
  return rows.map(mapProjectRow);
}

export async function getProject(projectId, ownerUserId) {
  const db = getPool();
  if (!db) {
    const project = projects.get(projectId) ?? null;
    if (!project || project.ownerUserId !== ownerUserId) {
      return null;
    }
    return project;
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_projects
     WHERE id = $1 AND owner_user_id = $2
     LIMIT 1`,
    [projectId, ownerUserId]
  );
  if (rows.length === 0) {
    return null;
  }
  return mapProjectRow(rows[0]);
}

export async function saveProject(input) {
  const now = new Date().toISOString();
  const project = createProject({
    ...input,
    createdAt: input.createdAt ?? now,
    updatedAt: now
  });
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_projects
        (id, owner_user_id, title, logline, target_duration_minutes, tone, current_phase, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (id)
       DO UPDATE SET
        owner_user_id = EXCLUDED.owner_user_id,
        title = EXCLUDED.title,
        logline = EXCLUDED.logline,
        target_duration_minutes = EXCLUDED.target_duration_minutes,
        tone = EXCLUDED.tone,
        current_phase = EXCLUDED.current_phase,
        updated_at = EXCLUDED.updated_at`,
      [
        project.id,
        project.ownerUserId,
        project.title,
        project.logline,
        project.targetDurationMinutes,
        project.tone,
        project.currentPhase,
        project.createdAt,
        project.updatedAt
      ]
    );
    return project;
  }
  projects.set(project.id, project);
  return project;
}

export async function deleteProject(projectId, ownerUserId) {
  const db = getPool();
  if (db) {
    const { rowCount } = await db.query(
      `DELETE FROM cinefuse_projects
       WHERE id = $1 AND owner_user_id = $2`,
      [projectId, ownerUserId]
    );
    return rowCount > 0;
  }

  const project = await getProject(projectId, ownerUserId);
  if (!project) {
    return false;
  }
  projects.delete(projectId);
  for (const [sceneId, scene] of scenes.entries()) {
    if (scene.projectId === projectId) {
      scenes.delete(sceneId);
    }
  }
  for (const [shotId, shot] of shots.entries()) {
    if (shot.projectId === projectId) {
      shots.delete(shotId);
    }
  }
  for (const [characterId, character] of characters.entries()) {
    if (character.projectId === projectId) {
      characters.delete(characterId);
    }
  }
  for (const [jobId, job] of jobs.entries()) {
    if (job.projectId === projectId) {
      jobs.delete(jobId);
    }
  }
  return true;
}

export async function listScenes(projectId) {
  const db = getPool();
  if (!db) {
    return Array.from(scenes.values())
      .filter((scene) => scene.projectId === projectId)
      .sort((a, b) => a.orderIndex - b.orderIndex);
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_scenes
     WHERE project_id = $1
     ORDER BY order_index, created_at`,
    [projectId]
  );
  return rows.map(mapSceneRow);
}

export async function listCharacters(projectId) {
  const db = getPool();
  if (!db) {
    return Array.from(characters.values())
      .filter((character) => character.projectId === projectId)
      .sort((a, b) => a.name.localeCompare(b.name));
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_characters
     WHERE project_id = $1
     ORDER BY created_at`,
    [projectId]
  );
  return rows.map(mapCharacterRow);
}

export async function saveCharacter(input) {
  const existing = characters.get(input.id);
  const now = new Date().toISOString();
  const character = {
    id: input.id,
    projectId: input.projectId,
    name: input.name ?? existing?.name ?? "Untitled Character",
    description: input.description ?? existing?.description ?? "",
    status: input.status ?? existing?.status ?? "draft",
    previewUrl: input.previewUrl ?? existing?.previewUrl ?? null,
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_characters
        (id, project_id, name, description, status, preview_url, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        status = EXCLUDED.status,
        preview_url = EXCLUDED.preview_url,
        updated_at = EXCLUDED.updated_at`,
      [
        character.id,
        character.projectId,
        character.name,
        character.description,
        character.status,
        character.previewUrl,
        character.createdAt,
        character.updatedAt
      ]
    );
    return character;
  }
  characters.set(character.id, character);
  return character;
}

export async function saveScene(input) {
  const existing = scenes.get(input.id);
  const now = new Date().toISOString();
  const scene = {
    id: input.id,
    projectId: input.projectId,
    orderIndex: input.orderIndex ?? existing?.orderIndex ?? 0,
    title: input.title ?? existing?.title ?? "Untitled Scene",
    description: input.description ?? existing?.description ?? "",
    mood: input.mood ?? existing?.mood ?? "drama",
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_scenes
        (id, project_id, order_index, title, description, mood, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        order_index = EXCLUDED.order_index,
        title = EXCLUDED.title,
        description = EXCLUDED.description,
        mood = EXCLUDED.mood,
        updated_at = EXCLUDED.updated_at`,
      [
        scene.id,
        scene.projectId,
        scene.orderIndex,
        scene.title,
        scene.description,
        scene.mood,
        scene.createdAt,
        scene.updatedAt
      ]
    );
    return scene;
  }
  scenes.set(scene.id, scene);
  return scene;
}

export async function listShots(projectId) {
  const db = getPool();
  if (!db) {
    return Array.from(shots.values()).filter((shot) => shot.projectId === projectId);
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_shots
     WHERE project_id = $1
     ORDER BY created_at`,
    [projectId]
  );
  return rows.map(mapShotRow);
}

export async function saveShot(input) {
  const existing = await getShot(input.id);
  const now = new Date().toISOString();
  const shot = {
    id: input.id,
    projectId: input.projectId,
    prompt: input.prompt ?? existing?.prompt ?? "",
    modelTier: input.modelTier ?? existing?.modelTier ?? "budget",
    status: input.status ?? existing?.status ?? "draft",
    clipUrl: input.clipUrl ?? existing?.clipUrl ?? null,
    characterLocks: input.characterLocks ?? existing?.characterLocks ?? [],
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_shots
        (id, project_id, prompt, model_tier, status, clip_url, character_locks, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        prompt = EXCLUDED.prompt,
        model_tier = EXCLUDED.model_tier,
        status = EXCLUDED.status,
        clip_url = EXCLUDED.clip_url,
        character_locks = EXCLUDED.character_locks,
        updated_at = EXCLUDED.updated_at`,
      [
        shot.id,
        shot.projectId,
        shot.prompt,
        shot.modelTier,
        shot.status,
        shot.clipUrl,
        JSON.stringify(shot.characterLocks ?? []),
        shot.createdAt,
        shot.updatedAt
      ]
    );
    return shot;
  }
  shots.set(shot.id, shot);
  return shot;
}

export async function getShot(shotId, projectId) {
  const db = getPool();
  if (db) {
    const { rows } = await db.query(
      `SELECT *
       FROM cinefuse_shots
       WHERE id = $1
       LIMIT 1`,
      [shotId]
    );
    if (rows.length === 0) {
      return null;
    }
    const shot = mapShotRow(rows[0]);
    if (projectId && shot.projectId !== projectId) {
      return null;
    }
    return shot;
  }

  const shot = shots.get(shotId) ?? null;
  if (!shot) {
    return null;
  }
  if (projectId && shot.projectId !== projectId) {
    return null;
  }
  return shot;
}

export async function listJobs(projectId) {
  const db = getPool();
  if (!db) {
    return Array.from(jobs.values()).filter((job) => job.projectId === projectId);
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_jobs
     WHERE project_id = $1
     ORDER BY created_at`,
    [projectId]
  );
  return rows.map(mapJobRow);
}

export async function saveJob(input) {
  const existing = await getJob(input.id);
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
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_jobs
        (id, project_id, shot_id, kind, status, input_payload, output_payload, cost_to_us_cents, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb,$8,$9,$10)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        shot_id = EXCLUDED.shot_id,
        kind = EXCLUDED.kind,
        status = EXCLUDED.status,
        input_payload = EXCLUDED.input_payload,
        output_payload = EXCLUDED.output_payload,
        cost_to_us_cents = EXCLUDED.cost_to_us_cents,
        updated_at = EXCLUDED.updated_at`,
      [
        job.id,
        job.projectId,
        job.shotId,
        job.kind,
        job.status,
        JSON.stringify(job.inputPayload ?? {}),
        JSON.stringify(job.outputPayload ?? {}),
        job.costToUsCents,
        job.createdAt,
        job.updatedAt
      ]
    );
    return job;
  }
  jobs.set(job.id, job);
  return job;
}

async function getJob(jobId) {
  const db = getPool();
  if (db) {
    const { rows } = await db.query(
      `SELECT *
       FROM cinefuse_jobs
       WHERE id = $1
       LIMIT 1`,
      [jobId]
    );
    return rows[0] ? mapJobRow(rows[0]) : null;
  }
  return jobs.get(jobId) ?? null;
}

export async function clearProjects() {
  const db = getPool();
  if (db) {
    await db.query(
      "TRUNCATE TABLE cinefuse_jobs, cinefuse_shots, cinefuse_characters, cinefuse_scenes, cinefuse_projects RESTART IDENTITY CASCADE"
    );
    return;
  }
  projects.clear();
  scenes.clear();
  characters.clear();
  shots.clear();
  jobs.clear();
}
