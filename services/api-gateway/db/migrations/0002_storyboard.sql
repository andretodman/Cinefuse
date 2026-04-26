CREATE TABLE IF NOT EXISTS cinefuse_scenes (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES cinefuse_projects(id) ON DELETE CASCADE,
  order_index INTEGER NOT NULL DEFAULT 0,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  mood TEXT NOT NULL DEFAULT 'drama',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cinefuse_scenes_project_id
  ON cinefuse_scenes(project_id);
