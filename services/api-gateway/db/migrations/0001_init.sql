CREATE TABLE IF NOT EXISTS cinefuse_projects (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  logline TEXT NOT NULL DEFAULT '',
  target_duration_minutes INTEGER NOT NULL DEFAULT 5,
  tone TEXT NOT NULL DEFAULT 'drama',
  current_phase TEXT NOT NULL DEFAULT 'script',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cinefuse_shots (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES cinefuse_projects(id) ON DELETE CASCADE,
  prompt TEXT NOT NULL DEFAULT '',
  model_tier TEXT NOT NULL DEFAULT 'budget',
  status TEXT NOT NULL DEFAULT 'draft',
  clip_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cinefuse_jobs (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES cinefuse_projects(id) ON DELETE CASCADE,
  shot_id TEXT REFERENCES cinefuse_shots(id) ON DELETE SET NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  input_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  output_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  cost_to_us_cents INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cinefuse_spark_transactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('debit', 'credit', 'iap_redeem')),
  amount INTEGER NOT NULL CHECK (amount >= 0),
  idempotency_key TEXT NOT NULL UNIQUE,
  related_resource_type TEXT,
  related_resource_id TEXT,
  balance_after INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cinefuse_projects_owner_user_id
  ON cinefuse_projects(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_cinefuse_shots_project_id
  ON cinefuse_shots(project_id);
CREATE INDEX IF NOT EXISTS idx_cinefuse_jobs_project_id
  ON cinefuse_jobs(project_id);
CREATE INDEX IF NOT EXISTS idx_cinefuse_jobs_shot_id
  ON cinefuse_jobs(shot_id);
CREATE INDEX IF NOT EXISTS idx_cinefuse_spark_transactions_user_id
  ON cinefuse_spark_transactions(user_id);
