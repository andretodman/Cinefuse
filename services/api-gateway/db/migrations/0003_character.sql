CREATE TABLE IF NOT EXISTS cinefuse_characters (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES cinefuse_projects(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'draft',
  preview_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cinefuse_characters_project_id
  ON cinefuse_characters(project_id);

ALTER TABLE cinefuse_shots
  ADD COLUMN IF NOT EXISTS character_locks JSONB NOT NULL DEFAULT '[]'::jsonb;
