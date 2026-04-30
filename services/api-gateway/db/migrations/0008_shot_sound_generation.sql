-- Persists ElevenLabs score options chosen at shot creation (audio workspace).
ALTER TABLE cinefuse_shots
  ADD COLUMN IF NOT EXISTS sound_generation JSONB NOT NULL DEFAULT '{}'::jsonb;
