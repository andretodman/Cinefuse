-- Binary blobs for gateway-served project uploads (worker ingest + client POST).
-- Required when multiple gateway instances serve GET …/files/:id (in-memory maps are per-process).

CREATE TABLE IF NOT EXISTS cinefuse_project_files (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES cinefuse_projects(id) ON DELETE CASCADE,
  filename TEXT NOT NULL,
  byte_size INTEGER NOT NULL DEFAULT 0,
  content BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cinefuse_project_files_project_id
  ON cinefuse_project_files(project_id);
