CREATE TABLE IF NOT EXISTS cinefuse_sound_blueprints (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES cinefuse_projects(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  template_id TEXT,
  reference_file_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cinefuse_sound_blueprints_project
  ON cinefuse_sound_blueprints(project_id);
