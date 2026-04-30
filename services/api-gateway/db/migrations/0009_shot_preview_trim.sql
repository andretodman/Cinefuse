-- Preview panel in/out trim (milliseconds from media start). NULL = full length.
ALTER TABLE cinefuse_shots
  ADD COLUMN IF NOT EXISTS preview_trim_in_ms INTEGER,
  ADD COLUMN IF NOT EXISTS preview_trim_out_ms INTEGER;
