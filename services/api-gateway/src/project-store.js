import { randomUUID } from "node:crypto";
import { createProject } from "../../../packages/shared-types/src/index.js";
import { Pool } from "pg";

const projects = new Map();
const scenes = new Map();
const characters = new Map();
const shots = new Map();
const audioTracks = new Map();
const soundBlueprints = new Map();
const jobs = new Map();
/** Staging registry for client uploads (Pubfuse Files IDs in production). Maps file id → owning project. */
const uploadedProjectFiles = new Map();

let pool;

export function registerUploadedProjectFile({ projectId, filename, byteSize }) {
  const id = randomUUID();
  const safeName = typeof filename === "string" && filename.length > 0 ? filename : "upload.bin";
  uploadedProjectFiles.set(id, {
    projectId,
    filename: safeName,
    byteSize: Number(byteSize) || 0,
    createdAt: new Date().toISOString()
  });
  return { id, filename: safeName, byteSize: Number(byteSize) || 0 };
}

export function validateUploadedFileIdsForProject(projectId, fileIds) {
  if (!Array.isArray(fileIds)) {
    return;
  }
  for (const fid of fileIds) {
    if (typeof fid !== "string" || fid.length === 0) {
      throw new Error("invalid file id");
    }
    const meta = uploadedProjectFiles.get(fid);
    if (!meta || meta.projectId !== projectId) {
      throw new Error(`unknown file id ${fid}`);
    }
  }
}

function parsePositiveInt(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.floor(parsed);
}

function looksLikeUnresolvedReference(value) {
  return typeof value === "string" && value.includes("${") && value.includes("}");
}

function stripInlineSSLRootCert(rawConnectionString) {
  if (typeof rawConnectionString !== "string") {
    return rawConnectionString;
  }
  const parameter = "sslrootcert=";
  const index = rawConnectionString.indexOf(parameter);
  if (index === -1) {
    return rawConnectionString;
  }
  const valueStart = index + parameter.length;
  const nextAmpersand = rawConnectionString.indexOf("&", valueStart);
  const valueEnd = nextAmpersand === -1 ? rawConnectionString.length : nextAmpersand;
  const value = rawConnectionString.slice(valueStart, valueEnd);
  const hasInlineCert = value.includes("BEGIN")
    || value.includes("CERTIFICATE")
    || /[\n\r\t]/.test(value);
  if (!hasInlineCert) {
    return rawConnectionString;
  }
  let removeStart = index;
  if (removeStart > 0 && (rawConnectionString[removeStart - 1] === "?" || rawConnectionString[removeStart - 1] === "&")) {
    removeStart -= 1;
  }
  let removeEnd = valueEnd;
  if (removeEnd < rawConnectionString.length && rawConnectionString[removeEnd] === "&") {
    removeEnd += 1;
  }
  return rawConnectionString.slice(0, removeStart) + rawConnectionString.slice(removeEnd);
}

function firstUsableConnectionString(...candidates) {
  for (const candidate of candidates) {
    if (typeof candidate !== "string" || candidate.trim().length === 0) {
      continue;
    }
    if (looksLikeUnresolvedReference(candidate)) {
      continue;
    }
    return stripInlineSSLRootCert(candidate.trim());
  }
  return null;
}

function resolveConnectionString() {
  if (process.env.NODE_ENV === "test") {
    return firstUsableConnectionString(
      process.env.CINEFUSE_DATABASE_URL_TEST,
      process.env.DATABASE_URL_TEST,
      process.env.CINEFUSE_DATABASE_URL,
      process.env.DATABASE_URL,
      process.env.DATABASE_URL_RESOLVED,
      process.env.POSTGRES_URL
    );
  }
  return firstUsableConnectionString(
    process.env.CINEFUSE_DATABASE_URL,
    process.env.DATABASE_URL,
    process.env.DATABASE_URL_RESOLVED,
    process.env.POSTGRES_URL
  );
}

function resolvePoolConfig(connectionString) {
  const config = {
    connectionString,
    // Fail fast when the DB is unreachable so UI doesn't hang indefinitely.
    connectionTimeoutMillis: parsePositiveInt(process.env.DATABASE_CONNECT_TIMEOUT_MS, 5000),
    query_timeout: parsePositiveInt(process.env.DATABASE_QUERY_TIMEOUT_MS, 10000),
    statement_timeout: parsePositiveInt(process.env.DATABASE_STATEMENT_TIMEOUT_MS, 10000)
  };
  const sslMode = extractSSLMode(connectionString);

  const sslEnabled = ["require", "verify-ca", "verify-full"].includes(sslMode)
    || (process.env.DATABASE_SSL ?? "").toLowerCase() === "true";
  if (!sslEnabled) {
    return config;
  }

  const explicitRejectUnauthorized = process.env.DATABASE_SSL_REJECT_UNAUTHORIZED;
  const rejectUnauthorized = explicitRejectUnauthorized
    ? explicitRejectUnauthorized !== "false"
    : sslMode === "verify-full";
  const ssl = { rejectUnauthorized };
  const sslCA = process.env.DATABASE_SSL_CA ?? process.env.PGSSLROOTCERT_CONTENT;
  if (sslCA) {
    ssl.ca = sslCA.replace(/\\n/g, "\n");
  }
  config.ssl = ssl;
  return config;
}

function extractSSLMode(connectionString) {
  if (typeof connectionString !== "string") {
    return "";
  }
  try {
    const parsed = new URL(connectionString);
    return (parsed.searchParams.get("sslmode") ?? "").toLowerCase();
  } catch {
    const match = connectionString.match(/(?:\?|&)sslmode=([^&]+)/i);
    if (!match || !match[1]) {
      return "";
    }
    try {
      return decodeURIComponent(match[1]).toLowerCase();
    } catch {
      return match[1].toLowerCase();
    }
  }
}

function getPool() {
  if (process.env.NODE_ENV === "test" && process.env.CINEFUSE_USE_DB_IN_TESTS !== "true") {
    return null;
  }
  const connectionString = resolveConnectionString();
  if (!connectionString) {
    return null;
  }
  if (!pool) {
    pool = new Pool(resolvePoolConfig(connectionString));
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
    orderIndex: row.order_index ?? 0,
    durationSec: row.duration_sec ?? null,
    thumbnailUrl: row.thumbnail_url ?? null,
    audioRefs: row.audio_refs ?? [],
    characterLocks: row.character_locks ?? [],
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapAudioTrackRow(row) {
  return {
    id: row.id,
    projectId: row.project_id,
    shotId: row.shot_id ?? null,
    kind: row.kind,
    title: row.title,
    sourceUrl: row.source_url ?? null,
    waveformUrl: row.waveform_url ?? null,
    laneIndex: row.lane_index ?? 0,
    startMs: row.start_ms ?? 0,
    durationMs: row.duration_ms ?? 0,
    status: row.status ?? "draft",
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

function memoryJobToRow(job) {
  return {
    id: job.id,
    project_id: job.projectId,
    shot_id: job.shotId,
    kind: job.kind,
    status: job.status,
    input_payload: job.inputPayload,
    output_payload: job.outputPayload,
    progress_pct: job.progressPct,
    cost_to_us_cents: job.costToUsCents,
    created_at: job.createdAt,
    updated_at: job.updatedAt
  };
}

function mapJobRow(row) {
  const inputPayload = row.input_payload ?? {};
  const outputPayload = row.output_payload ?? {};
  const progressPct = normalizeProgressPct(
    row.progress_pct ?? outputPayload.progressPct ?? outputPayload.progress_pct
  );
  const outputUrl = outputPayload.clipUrl
    ?? outputPayload.fileUrl
    ?? outputPayload.stitchedUrl
    ?? outputPayload.exportUrl
    ?? outputPayload.outputUrl
    ?? (typeof outputPayload.track?.sourceUrl === "string" ? outputPayload.track.sourceUrl : null)
    ?? null;
  const skippedFeature = Boolean(outputPayload.skippedFeature);
  const featureError = outputPayload.featureError ?? null;
  const providerAdapter = typeof outputPayload.providerAdapter === "string"
    ? outputPayload.providerAdapter
    : null;
  const outputCreated = outputPayload.outputCreated === undefined
    ? null
    : Boolean(outputPayload.outputCreated);
  return {
    id: row.id,
    projectId: row.project_id,
    shotId: row.shot_id,
    kind: row.kind,
    status: row.status,
    inputPayload,
    outputPayload,
    progressPct,
    costToUsCents: row.cost_to_us_cents ?? 0,
    promptText: typeof inputPayload.prompt === "string" ? inputPayload.prompt : null,
    modelId: typeof outputPayload.modelId === "string" ? outputPayload.modelId : null,
    errorMessage: typeof outputPayload.error === "string" ? outputPayload.error : null,
    outputUrl: typeof outputUrl === "string" ? outputUrl : null,
    skippedFeature,
    featureError,
    providerAdapter,
    outputCreated,
    requestId: typeof (outputPayload.requestId ?? outputPayload.request_id) === "string"
      ? (outputPayload.requestId ?? outputPayload.request_id)
      : null,
    idempotencyKey: typeof inputPayload.idempotencyKey === "string" ? inputPayload.idempotencyKey : null,
    invokeState: typeof outputPayload.invokeState === "string" ? outputPayload.invokeState : null,
    falEndpoint: typeof outputPayload.falEndpoint === "string" ? outputPayload.falEndpoint : null,
    falStatusUrl: typeof outputPayload.falStatusUrl === "string" ? outputPayload.falStatusUrl : null,
    providerStatusCode: Number.isFinite(Number(outputPayload.providerStatusCode))
      ? Number(outputPayload.providerStatusCode)
      : null,
    providerResponseSnippet: typeof outputPayload.providerResponseSnippet === "string"
      ? outputPayload.providerResponseSnippet
      : null,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function normalizeProgressPct(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return null;
  }
  return Math.max(0, Math.min(100, Math.round(parsed)));
}

function mapCharacterRow(row) {
  return {
    id: row.id,
    projectId: row.project_id,
    name: row.name,
    description: row.description,
    status: row.status,
    previewUrl: row.preview_url,
    consistencyScore: row.consistency_score ?? null,
    consistencyThreshold: row.consistency_threshold ?? null,
    consistencyPassed: row.consistency_passed ?? false,
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
  for (const [trackId, track] of audioTracks.entries()) {
    if (track.projectId === projectId) {
      audioTracks.delete(trackId);
    }
  }
  for (const [jobId, job] of jobs.entries()) {
    if (job.projectId === projectId) {
      jobs.delete(jobId);
    }
  }
  for (const [blueprintId, blueprint] of soundBlueprints.entries()) {
    if (blueprint.projectId === projectId) {
      soundBlueprints.delete(blueprintId);
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
    consistencyScore: input.consistencyScore ?? existing?.consistencyScore ?? null,
    consistencyThreshold: input.consistencyThreshold ?? existing?.consistencyThreshold ?? null,
    consistencyPassed: input.consistencyPassed ?? existing?.consistencyPassed ?? false,
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_characters
        (id, project_id, name, description, status, preview_url, consistency_score, consistency_threshold, consistency_passed, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        status = EXCLUDED.status,
        preview_url = EXCLUDED.preview_url,
        consistency_score = EXCLUDED.consistency_score,
        consistency_threshold = EXCLUDED.consistency_threshold,
        consistency_passed = EXCLUDED.consistency_passed,
        updated_at = EXCLUDED.updated_at`,
      [
        character.id,
        character.projectId,
        character.name,
        character.description,
        character.status,
        character.previewUrl,
        character.consistencyScore,
        character.consistencyThreshold,
        character.consistencyPassed,
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
    return Array.from(shots.values())
      .filter((shot) => shot.projectId === projectId)
      .sort((a, b) => (a.orderIndex ?? 0) - (b.orderIndex ?? 0));
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_shots
     WHERE project_id = $1
     ORDER BY order_index, created_at`,
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
    orderIndex: input.orderIndex ?? existing?.orderIndex ?? 0,
    durationSec: input.durationSec ?? existing?.durationSec ?? null,
    thumbnailUrl: input.thumbnailUrl ?? existing?.thumbnailUrl ?? null,
    audioRefs: input.audioRefs ?? existing?.audioRefs ?? [],
    characterLocks: input.characterLocks ?? existing?.characterLocks ?? [],
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_shots
        (id, project_id, prompt, model_tier, status, clip_url, order_index, duration_sec, thumbnail_url, audio_refs, character_locks, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11::jsonb,$12,$13)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        prompt = EXCLUDED.prompt,
        model_tier = EXCLUDED.model_tier,
        status = EXCLUDED.status,
        clip_url = EXCLUDED.clip_url,
        order_index = EXCLUDED.order_index,
        duration_sec = EXCLUDED.duration_sec,
        thumbnail_url = EXCLUDED.thumbnail_url,
        audio_refs = EXCLUDED.audio_refs,
        character_locks = EXCLUDED.character_locks,
        updated_at = EXCLUDED.updated_at`,
      [
        shot.id,
        shot.projectId,
        shot.prompt,
        shot.modelTier,
        shot.status,
        shot.clipUrl,
        shot.orderIndex,
        shot.durationSec,
        shot.thumbnailUrl,
        JSON.stringify(shot.audioRefs ?? []),
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

export async function deleteShot(shotId, projectId) {
  const db = getPool();
  if (db) {
    await db.query("BEGIN");
    try {
      await db.query(
        `DELETE FROM cinefuse_jobs
         WHERE shot_id = $1 AND project_id = $2`,
        [shotId, projectId]
      );
      const { rowCount } = await db.query(
        `DELETE FROM cinefuse_shots
         WHERE id = $1 AND project_id = $2`,
        [shotId, projectId]
      );
      await db.query("COMMIT");
      return rowCount > 0;
    } catch (error) {
      await db.query("ROLLBACK");
      throw error;
    }
  }

  const shot = shots.get(shotId);
  if (!shot || shot.projectId !== projectId) {
    return false;
  }
  shots.delete(shotId);
  for (const [jobId, job] of jobs.entries()) {
    if (job.shotId === shotId && job.projectId === projectId) {
      jobs.delete(jobId);
    }
  }
  return true;
}

export async function listAudioTracks(projectId) {
  const db = getPool();
  if (!db) {
    return Array.from(audioTracks.values())
      .filter((track) => track.projectId === projectId)
      .sort((a, b) => (a.laneIndex - b.laneIndex) || (a.startMs - b.startMs));
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_audio_tracks
     WHERE project_id = $1
     ORDER BY lane_index, start_ms, created_at`,
    [projectId]
  );
  return rows.map(mapAudioTrackRow);
}

export async function saveAudioTrack(input) {
  const existing = audioTracks.get(input.id);
  const now = new Date().toISOString();
  const track = {
    id: input.id,
    projectId: input.projectId,
    shotId: input.shotId ?? existing?.shotId ?? null,
    kind: input.kind ?? existing?.kind ?? "score",
    title: input.title ?? existing?.title ?? "Untitled Track",
    sourceUrl: input.sourceUrl ?? existing?.sourceUrl ?? null,
    waveformUrl: input.waveformUrl ?? existing?.waveformUrl ?? null,
    laneIndex: input.laneIndex ?? existing?.laneIndex ?? 0,
    startMs: input.startMs ?? existing?.startMs ?? 0,
    durationMs: input.durationMs ?? existing?.durationMs ?? 0,
    status: input.status ?? existing?.status ?? "draft",
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_audio_tracks
        (id, project_id, shot_id, kind, title, source_url, waveform_url, lane_index, start_ms, duration_ms, status, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        shot_id = EXCLUDED.shot_id,
        kind = EXCLUDED.kind,
        title = EXCLUDED.title,
        source_url = EXCLUDED.source_url,
        waveform_url = EXCLUDED.waveform_url,
        lane_index = EXCLUDED.lane_index,
        start_ms = EXCLUDED.start_ms,
        duration_ms = EXCLUDED.duration_ms,
        status = EXCLUDED.status,
        updated_at = EXCLUDED.updated_at`,
      [
        track.id,
        track.projectId,
        track.shotId,
        track.kind,
        track.title,
        track.sourceUrl,
        track.waveformUrl,
        track.laneIndex,
        track.startMs,
        track.durationMs,
        track.status,
        track.createdAt,
        track.updatedAt
      ]
    );
    return track;
  }
  audioTracks.set(track.id, track);
  return track;
}

function mapSoundBlueprintRow(row) {
  let ids = [];
  const refs = row.reference_file_ids;
  if (Array.isArray(refs)) {
    ids = refs;
  } else if (refs && typeof refs === "object") {
    ids = Object.values(refs);
  } else if (typeof refs === "string") {
    try {
      const parsed = JSON.parse(refs);
      ids = Array.isArray(parsed) ? parsed : [];
    } catch {
      ids = [];
    }
  }
  return {
    id: row.id,
    projectId: row.project_id,
    name: row.name,
    templateId: row.template_id ?? null,
    referenceFileIds: ids,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export async function listSoundBlueprints(projectId) {
  const db = getPool();
  if (!db) {
    return Array.from(soundBlueprints.values())
      .filter((blueprint) => blueprint.projectId === projectId)
      .sort((a, b) => a.name.localeCompare(b.name));
  }
  const { rows } = await db.query(
    `SELECT *
     FROM cinefuse_sound_blueprints
     WHERE project_id = $1
     ORDER BY created_at`,
    [projectId]
  );
  return rows.map(mapSoundBlueprintRow);
}

export async function saveSoundBlueprint(input) {
  const existing = soundBlueprints.get(input.id);
  const now = new Date().toISOString();
  const blueprint = {
    id: input.id,
    projectId: input.projectId,
    name: input.name ?? existing?.name ?? "Sound blueprint",
    templateId: input.templateId ?? existing?.templateId ?? null,
    referenceFileIds: Array.isArray(input.referenceFileIds)
      ? input.referenceFileIds
      : (existing?.referenceFileIds ?? []),
    createdAt: existing?.createdAt ?? input.createdAt ?? now,
    updatedAt: now
  };
  const db = getPool();
  if (db) {
    await db.query(
      `INSERT INTO cinefuse_sound_blueprints
        (id, project_id, name, template_id, reference_file_ids, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7)
       ON CONFLICT (id)
       DO UPDATE SET
        project_id = EXCLUDED.project_id,
        name = EXCLUDED.name,
        template_id = EXCLUDED.template_id,
        reference_file_ids = EXCLUDED.reference_file_ids,
        updated_at = EXCLUDED.updated_at`,
      [
        blueprint.id,
        blueprint.projectId,
        blueprint.name,
        blueprint.templateId,
        JSON.stringify(blueprint.referenceFileIds ?? []),
        blueprint.createdAt,
        blueprint.updatedAt
      ]
    );
    return blueprint;
  }
  soundBlueprints.set(blueprint.id, blueprint);
  return blueprint;
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
    return Array.from(jobs.values())
      .filter((job) => job.projectId === projectId)
      .map((job) => mapJobRow(memoryJobToRow(job)));
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
  const outputPayload = {
    ...(existing?.outputPayload ?? {}),
    ...(input.outputPayload ?? {})
  };
  const progressPct = normalizeProgressPct(
    input.progressPct
      ?? outputPayload.progressPct
      ?? outputPayload.progress_pct
      ?? existing?.progressPct
  );
  if (progressPct === null) {
    delete outputPayload.progressPct;
    delete outputPayload.progress_pct;
  } else {
    outputPayload.progressPct = progressPct;
    delete outputPayload.progress_pct;
  }
  const job = {
    id: input.id,
    projectId: input.projectId ?? existing?.projectId,
    shotId: input.shotId ?? existing?.shotId ?? null,
    kind: input.kind ?? existing?.kind ?? "clip",
    status: input.status ?? existing?.status ?? "queued",
    inputPayload: input.inputPayload ?? existing?.inputPayload ?? {},
    outputPayload,
    progressPct,
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

export async function getJob(jobId, projectId) {
  const db = getPool();
  if (db) {
    const { rows } = await db.query(
      `SELECT *
       FROM cinefuse_jobs
       WHERE id = $1
       LIMIT 1`,
      [jobId]
    );
    if (!rows[0]) {
      return null;
    }
    const job = mapJobRow(rows[0]);
    if (projectId && job.projectId !== projectId) {
      return null;
    }
    return job;
  }
  const job = jobs.get(jobId) ?? null;
  if (!job) {
    return null;
  }
  if (projectId && job.projectId !== projectId) {
    return null;
  }
  return mapJobRow(memoryJobToRow(job));
}

export async function deleteJob(jobId, projectId) {
  const db = getPool();
  if (db) {
    const { rowCount } = await db.query(
      `DELETE FROM cinefuse_jobs
       WHERE id = $1 AND project_id = $2`,
      [jobId, projectId]
    );
    return rowCount > 0;
  }
  const job = jobs.get(jobId);
  if (!job || job.projectId !== projectId) {
    return false;
  }
  jobs.delete(jobId);
  return true;
}

export async function clearProjects() {
  const db = getPool();
  if (db) {
    await db.query(
      "TRUNCATE TABLE cinefuse_jobs, cinefuse_audio_tracks, cinefuse_sound_blueprints, cinefuse_shots, cinefuse_characters, cinefuse_scenes, cinefuse_projects RESTART IDENTITY CASCADE"
    );
    return;
  }
  projects.clear();
  scenes.clear();
  characters.clear();
  shots.clear();
  audioTracks.clear();
  soundBlueprints.clear();
  jobs.clear();
  uploadedProjectFiles.clear();
}
