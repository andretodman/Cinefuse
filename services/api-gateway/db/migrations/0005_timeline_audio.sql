ALTER TABLE cinefuse_shots
  ADD COLUMN IF NOT EXISTS order_index INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS duration_sec INTEGER,
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT,
  ADD COLUMN IF NOT EXISTS audio_refs JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_cinefuse_shots_project_order
  ON cinefuse_shots(project_id, order_index);

CREATE TABLE IF NOT EXISTS cinefuse_audio_tracks (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES cinefuse_projects(id) ON DELETE CASCADE,
  shot_id TEXT REFERENCES cinefuse_shots(id) ON DELETE SET NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  source_url TEXT,
  waveform_url TEXT,
  lane_index INTEGER NOT NULL DEFAULT 0,
  start_ms INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cinefuse_audio_tracks_project
  ON cinefuse_audio_tracks(project_id, lane_index, start_ms);
