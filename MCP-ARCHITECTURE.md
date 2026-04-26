# MCP-ARCHITECTURE.md — Cinefuse MCP Server Specifications

This file is the technical contract for the eight MCP servers that compose Cinefuse's generation backend. Each server has a defined tool surface and is independently deployable. New features extend an existing server (new tool) or add a new server (new bounded domain). Both Cursor and Claude Code introspect these MCPs at session start, so the tool descriptions in code are the only documentation that matters at runtime.

This file documents *intent and shape*. The MCP tool definitions in code are the source of truth for parameter names, types, and schemas. When the two disagree, the code is right and this file is updated.

## Why MCPs at all

The conventional alternative to MCPs is a set of internal HTTP services with hand-written client SDKs. We're choosing MCPs because every tool we build is also a tool we want AI agents — Cursor, Claude Code, and (eventually) end-user-facing Cinefuse agents — to use. With MCPs the tool surface is self-describing; we don't write a client SDK *and* an OpenAPI spec *and* an LLM tool schema. We write the MCP, and all consumers read the same definition.

The cost is some overhead per call relative to a hand-tuned RPC. For our scale (thousands of generations per day, not millions per second), the overhead is negligible. The benefit — a single point of definition, automatic agent compatibility, easy local-vs-remote symmetry — is large.

## Transport and hosting

In production, each MCP runs as its own service in ECS (Fargate) behind the API gateway. The gateway is also an MCP host: it receives an HTTPS request from the Mac app or web, authenticates the user, and dispatches to the appropriate MCP via internal stdio/HTTP-MCP transport. Workers (Python render-worker) consume tasks from a Redis queue and call MCPs directly.

Locally and inside the Mac app, MCPs run in-process: the Mac app embeds a Node MCP host that loads the MCPs as JS modules. This is fine because all the MCPs' real work — model inference, ffmpeg, Pubfuse calls — happens via outbound HTTP, not in the MCP's local process. The MCP code itself is thin orchestration.

Authentication between the API gateway and the MCPs uses signed internal tokens (HMAC over the request body with a service-account secret). User identity is passed through as a `cinefuse_user_id` field on every tool call; MCPs do not authenticate the user themselves, but they do enforce that the caller has supplied a user ID and rejected if not. The `billing` MCP additionally enforces idempotency-key uniqueness as a hard contract.

The external HTTP contract used by clients is versioned under `/api/v1/cinefuse/*`. Canonical routes are documented in `docs/CINEFUSE-API-CONTRACT.md` and include project, shot, and job resources (`/projects`, `/projects/{id}/shots`, `/projects/{id}/jobs`). Legacy `/v1/projects` is a temporary gateway alias during migration only.

## Per-server specifications

Each section below covers: purpose, dependencies, tool surface (intent only — schemas in code), failure modes, and notable invariants.

---

### `mcp/pubfuse`

**Purpose.** The thin wrapper around Pubfuse REST. This is the single point of HTTP contact with Pubfuse from anywhere in the Cinefuse codebase.

**Dependencies.** Pubfuse REST API, configured per-environment via the SDK Client API key + HMAC secret in Secrets Manager. No database, no other MCPs.

**Tool surface.**

`get_user(user_id)` — returns Pubfuse user profile (display name, avatar, email, created_at). Cached for 60 seconds in Redis to avoid Pubfuse rate limits on hot paths.

`update_profile(user_id, fields)` — partial update of profile fields. Validates allowed fields against an allowlist before forwarding.

`list_files(user_id, prefix, limit, cursor)` — paginated file listing. Used by the Mac app's "open project from Pubfuse" flow.

`upload_file(user_id, key, blob, content_type, metadata)` — uploads to Pubfuse Files. Returns the file ID and public URL. Metadata includes Cinefuse-specific tags like `project_id`, `kind` (clip / audio / archive / export), and `tier`.

`get_file_url(file_id, mode)` — returns either the authenticated URL (for the user's own access) or the public URL (for sharing / for LiveKit egress consumption).

`create_scheduled_event(user_id, project_id, start_time, video_file_id, ...)` — creates a Pubfuse scheduled playback event for sharing a finished movie. Uses Pubfuse's scheduled event API.

`get_spark_balance(user_id)` — reads the cached balance off the Pubfuse user record. The `billing` MCP is the source of truth for the ledger; this is a fast read for UI.

`verify_webhook_hmac(headers, body, secret)` — utility for webhook receivers to validate Pubfuse-originated webhooks. Pure function; no I/O.

**Failure modes.** Pubfuse 5xx triggers retry with exponential backoff (3 attempts, then surface the error). Pubfuse 401 from a session token triggers a refresh-flow signal back to the caller; the caller (typically the API gateway) refreshes the token and retries once. Pubfuse rate limits (429) block the calling tool with a structured "rate limited" error and a retry-after hint.

**Invariant.** This MCP contains no business logic. If a function has more than translate-and-forward, it's in the wrong MCP.

---

### `mcp/billing`

**Purpose.** The Spark ledger. The only thing that writes to `cinefuse_spark_transactions` and the only thing that reconciles against the cached balance.

**Dependencies.** Postgres (`cinefuse_spark_transactions` and `cinefuse_iap_receipts` tables). Apple StoreKit verification endpoint (for `redeem_iap_receipt`). The `pubfuse` MCP for refreshing the cached balance on the user record.

**Tool surface.**

`quote_cost(action_kind, params)` — returns a Sparks cost for a planned action without committing. Pure function over the routing config + params (e.g., `action_kind=generate_clip`, `params={tier: 'standard', duration_seconds: 5, character_lock: true}`).

`debit(user_id, amount, idempotency_key, related_resource_type, related_resource_id, metadata)` — atomic debit. Writes a ledger row, updates the cached balance. Returns the new balance and transaction ID. Idempotency: if the same key is seen again, the original transaction ID is returned without a second debit.

`credit(user_id, amount, idempotency_key, kind, related_resource_type, related_resource_id, metadata)` — atomic credit. Used for refunds, promotional grants, IAP redemption (via `redeem_iap_receipt` → calls credit internally), referral bonuses.

`get_balance(user_id)` — the authoritative balance. Computed from the ledger sum, not the cached field, because the cached field is best-effort.

`redeem_iap_receipt(user_id, receipt_blob, expected_product_id)` — validates an Apple StoreKit receipt against Apple's verification API (sandbox or production based on environment), records the `cinefuse_iap_receipts` row to prevent double-redemption, and credits the appropriate Spark count for the SKU.

`list_transactions(user_id, since, limit, cursor)` — read-only paginated transaction history.

`reconcile_balance(user_id)` — recomputes the cached balance from the ledger. Run nightly across all users; can be invoked ad-hoc by support.

**Failure modes.** Apple verification failures: receipts with status 21002–21099 get specific handling per Apple's table. Postgres write failures: the operation rolls back; the caller retries with the same idempotency key (no double-spend). A duplicate idempotency key on a debit returns the original transaction without spending again, ensuring retries are safe.

**Invariants.** The ledger is append-only — no UPDATEs, no DELETEs, ever. The cached balance equals the sum of all credit transactions minus the sum of all debit transactions. A debit is rejected if it would make the balance negative (with a structured "insufficient sparks" error including the current balance and the shortfall).

---

### `mcp/script`

**Purpose.** Generate and revise screenplay structure. The user's narrative source-of-truth.

**Dependencies.** Anthropic API (Claude). Postgres (project / scene / character / dialogue rows). The `billing` MCP for cost quoting and debiting.

**Tool surface.**

`generate_beat_sheet(project_id, logline, target_duration_minutes, tone, optional_references)` — produces a structured beat sheet of 8–15 scenes. Each scene has a description, location, time-of-day, mood, character list, and 2–6 proposed shots with one-line prompts. Returns the full structure; the API gateway persists it.

`revise_scene(scene_id, instructions)` — rewrites a single scene given user instructions ("make this scene more tense," "remove the secondary character," etc.). Returns the revised scene structure.

`generate_shot_prompts(scene_id, count_target, style)` — given an existing scene, produces or replaces the shot list. Used when the user wants more shots or a different shot decomposition.

`extract_characters(project_id)` — re-runs character extraction over the current beat sheet. Used after substantial scene revisions to keep the character list in sync.

`extract_dialogue(scene_id)` — produces a structured list of dialogue lines for a scene, with speaker IDs (matching the project's character list). Used by the Audio tab.

`revise_dialogue(scene_id, line_id, instructions)` — single-line dialogue rewrite.

**Failure modes.** Claude API rate limits trigger backoff up to 60s, then surface the error. Output validation: every output is checked against the expected JSON schema before being returned; malformed outputs trigger one regeneration attempt before failing the call.

**Invariants.** The script is *always* structured JSON. We do not store free-text screenplays internally; the .fountain or .pdf export is generated at export time from the structured representation. This makes scene reordering, character renaming, and selective regeneration trivially safe.

---

### `mcp/character`

**Purpose.** Manage character identity. Cross-shot consistency is the hardest creative-pipeline problem; this MCP is where it's solved.

**Dependencies.** GPU compute (self-hosted in Phase 3, fal.ai LoRA training endpoint in Phase 1–2). The `pubfuse` MCP for storing reference images and trained LoRA weights. Postgres for the character record.

**Tool surface.**

`create_character(project_id, name, description, reference_image_urls, kind)` — creates a character record. `kind` is `'hero'` (will train a LoRA) or `'bit'` (uses IP-Adapter conditioning per shot, no training).

`train_identity(character_id)` — for hero characters: triggers the Stand-In LoRA training run on Wan 2.x. Returns when training completes; takes 3–8 minutes. The trained LoRA file is stored in Pubfuse Files. Costs ~500 Sparks (debited via `billing`).

`embed_identity(character_id)` — for bit characters: extracts a face/style embedding from the reference image(s) using a face encoder (InsightFace or similar) and stores it on the character record. Cheap (~50 Sparks).

`list_characters(project_id)` — read-only listing of all characters in a project, including their kind, training status, and preview URL.

`delete_character(character_id)` — removes the character record, deletes the LoRA file from Pubfuse Files. Does not retroactively un-condition shots that were generated with this character; those are immutable artifacts.

`preview_character(character_id, prompt)` — generates a single 1–2 second preview clip showing the character in a new scene, so the user can verify identity lock before generating real shots. Costs ~30 Sparks.

**Failure modes.** Training fails (rare): Sparks refunded automatically, user shown a "training didn't converge — try with different reference images" message. Reference image is rejected by content policy: clear error with the specific reason. GPU capacity unavailable: queued with an estimated wait time shown to the user.

**Invariants.** Character LoRAs are scoped to a single project — we do not aggregate user characters into a foundation training set. This is both a privacy commitment and a technical simplification.

---

### `mcp/clip`

**Purpose.** Generate video clips. The largest cost center.

**Dependencies.** fal.ai (or other inference providers per the routing config). The `character` MCP for retrieving character LoRAs / embeddings. The `billing` MCP for cost quote and debit. The `pubfuse` MCP for storing the resulting MP4.

**Tool surface.**

`quote_clip(prompt, tier, duration_seconds, has_character_lock, has_starting_image)` — returns Sparks cost without generating. Used by the API gateway to show the cost preview to the user.

`generate_clip(project_id, scene_id, shot_id, prompt, tier, duration_seconds, character_locks, starting_image_url, motion_reference_url, idempotency_key)` — generates a clip. Routes to the appropriate model based on the tier and shot characteristics (the routing logic is data-driven via a YAML config in this package). Debits Sparks. Returns the MP4 URL, thumbnail, model used, seed, and actual duration.

`regenerate_clip(shot_id, idempotency_key, prompt_override, seed_override)` — re-generates the same shot. By default uses the original prompt and a new random seed. Sparks cost is the same as a fresh generation; we don't discount regenerations because the user is consuming the same compute.

`list_models()` — reports the current routing config — which models are available per tier and what their current Sparks costs are. Used by the Mac app to render an "advanced model picker" for power users in Phase 3.

**Failure modes.** Provider rate limit: retry up to 3 times with backoff, then refund Sparks and surface to user. Provider content refusal: refund Sparks, show the user the provider's refusal text verbatim. Output validation failure (malformed MP4, wrong duration, etc.): regenerate once internally, then refund and surface. Slow generation (>5 min): emit progress events via SSE; the Mac app shows a "still working — about X minutes left" UI.

**Invariants.** Every clip generation captures `cost_to_us_cents` from the provider's response (where available) or estimated from the per-second rate. The `model_used` field on the resulting `Shot` record is exactly which model produced the output, even when routing fell back through multiple options.

---

### `mcp/audio`

**Purpose.** Generate and mix dialogue, score, and SFX.

**Dependencies.** ElevenLabs API (TTS). Suno API (music). Stable Audio Open or AudioGen (SFX generation). Static SFX library hosted in Pubfuse Files (Freesound CC0 selections, ~5,000 cues curated). Python audio processing (pydub, ffmpeg). `billing` and `pubfuse` MCPs.

**Tool surface.**

`generate_dialogue(scene_id, lines, voice_assignments, idempotency_key)` — generates dialogue audio. `lines` is the structured dialogue from the script MCP; `voice_assignments` maps each speaker to an ElevenLabs voice ID (either a stock voice or one of the user's custom-cloned voices). Returns a multi-track WAV (one track per character) plus a mixed dialogue track.

`generate_score(scene_id, mood, duration_seconds, tier, idempotency_key)` — generates score audio. Tier picks Suno (Standard) or self-hosted MusicGen (Budget).

`lookup_sfx(query, mood, duration_max)` — searches the SFX library. Returns matching cue URLs. Free.

`generate_sfx(description, duration_seconds, idempotency_key)` — generates a one-off SFX cue when the library doesn't have what's needed.

`mix_scene(scene_id, dialogue_track_url, score_track_url, sfx_cues, levels)` — mixes the three layers per scene. Levels are user-controllable. Output is a single mixed WAV at -14 LUFS. Free (we provide the mixing CPU time).

`lipsync(clip_url, dialogue_track_url, idempotency_key)` — for non-Veo clips, post-processes the clip to align mouth movements to the dialogue. Uses a Wav2Lip-style model (or successor in 2026). Returns a new clip URL. Costs ~20 Sparks per minute of dialogue.

**Failure modes.** ElevenLabs rate limit: queue and retry. Voice clone rejected (content): clear error to user. Mix produces silent output (rare bug): regenerate once, then surface.

**Invariants.** All output audio is normalized to -14 LUFS at the scene level before the user previews it; final-mix LUFS may shift slightly during stitch's per-project normalization pass, but per-scene the user can rely on consistent levels.

---

### `mcp/stitch`

**Purpose.** Assemble the project timeline into a single composited video.

**Dependencies.** ffmpeg (heavy use). The `pubfuse` MCP for input clip URLs and output upload. No external AI calls in this MCP — it's pure compute.

**Tool surface.**

`preview_stitch(project_id, idempotency_key)` — generates a low-res draft (480p, 30 fps) for in-editor preview. Optimized for speed, not quality. Uses cached intermediate fragments where possible.

`final_stitch(project_id, settings, idempotency_key)` — full-res stitch at 1080p (or 4K if `settings.resolution == '4k'`). Used as input to `export.encode_final`. Settings include transition specs per scene boundary, color match strength, captions on/off.

`apply_transitions(project_id, transitions)` — separately invocable for the case where the user wants to adjust transitions without a full restitch. Returns updated project state.

`color_match(project_id, strength)` — runs the per-pair color-match pass over the timeline. Adjustable strength because some users want the "AI cuts" aesthetic preserved.

`bake_captions(project_id, captions_vtt, options)` — embeds captions either as a soft VTT track or as hard-burned overlays.

`loudness_normalize(audio_track_url, target_lufs)` — single-track normalization utility. Used by both `audio.mix_scene` and `stitch.final_stitch`.

**Failure modes.** ffmpeg OOM on long timelines (>5 min at 4K): the MCP automatically chunks into 30-second windows and concatenates. ffmpeg crash on malformed input: surfaced clearly with the offending file. Disk pressure on the worker: drains the queue and restarts.

**Invariants.** A stitch operation is deterministic given the same inputs and settings — running it twice produces byte-identical (or near-identical, allowing for ffmpeg encoder non-determinism) output. This is what enables caching and partial-restitch optimization.

---

### `mcp/export`

**Purpose.** Final encode and distribution.

**Dependencies.** ffmpeg (final encode). C2PA library (watermarking). The `pubfuse` MCP (file storage and scheduled-event publication). Optional YouTube Data API and Vimeo API (for direct upload).

**Tool surface.**

`encode_final(stitched_url, settings, idempotency_key)` — re-encodes the stitched video to the final delivery format. 1080p H.264 by default; H.265 for 4K. Embeds the C2PA content credential. Returns the final MP4 URL in Pubfuse Files.

`upload_to_pubfuse(project_id, file_url, visibility)` — registers the project with Pubfuse for sharing. `visibility` is `private` (default), `unlisted` (URL works, not discoverable), or `public` (Pubfuse community feed).

`publish_to_pubfuse_stream(project_id, schedule_time)` — creates a scheduled non-live playback event so others can watch the finished movie at a specific time, using the `pubfuse.create_scheduled_event` tool.

`archive_project(project_id)` — bundles the script JSON, all clip MP4s, all audio tracks, and a manifest into a single ZIP, uploads to Pubfuse Files, and returns the URL. The user can re-import this archive later or migrate to another tool. Free.

`connect_youtube(user_id)` / `publish_to_youtube(project_id, oauth_token, metadata)` — OAuth flow and direct upload to the user's YouTube. OAuth tokens stored encrypted; revocable.

`connect_vimeo(user_id)` / `publish_to_vimeo(project_id, oauth_token, metadata)` — same, for Vimeo.

**Failure modes.** Encode fails (rare): retried automatically. Upload to Pubfuse fails: retried with backoff; final failure surfaces clearly. YouTube quota exhausted: queued for retry the next day.

**Invariants.** Every exported file embeds a C2PA content credential identifying it as AI-generated and listing the upstream models. This is non-negotiable. The user can opt out only on Premium tier and only with a deliberate UI action that includes a regulatory disclosure.

---

## Cross-cutting concerns

**Tracing.** Every MCP tool call is wrapped in OpenTelemetry. Spans propagate from the Mac app through the API gateway through the MCPs. We can answer "where did this user's last 60 seconds go?" with one query.

**Logging.** Structured JSON logs to CloudWatch (or Pubfuse-managed equivalent). Every log line has `trace_id`, `user_id`, `mcp_server`, `tool_name`, `duration_ms`, `outcome` (`ok` / `error`). Prompts and generated content are not logged; we log file IDs and metadata only.

**Cost capture.** Any MCP call that incurs a third-party cost records `cost_to_us_cents` on the related `RenderJob` row. This is checked in CI via a static analysis: any new HTTP call to a known-paid endpoint must be accompanied by a cost-capture line, or CI fails.

**Idempotency.** Mutating tool calls take an `idempotency_key` parameter. The MCP records the key alongside the result; subsequent calls with the same key return the cached result without re-executing. Default expiry is 24 hours. The Mac app generates idempotency keys deterministically from the operation's input hash, so retries-on-network-failure are safe.

**Rate limiting.** Per-user concurrent generation limits enforced at the API gateway (not in the MCPs themselves; MCPs trust their callers but the gateway is paranoid about external requests). Default: 3 concurrent budget jobs, 1 concurrent premium job, configurable per-subscription-tier (Pro users get 5 / 2).

**Versioning.** MCPs are versioned by package version. Breaking changes to a tool surface require a major version bump and a deprecation period. The API gateway can pin to a specific MCP version per environment, so we can roll out a new version to staging without touching prod.

## Adding a new MCP — checklist

When you add a new MCP server (a genuinely new bounded domain that doesn't fit in the existing eight), follow this checklist:

1. Create `mcp/<n>/` with the standard package layout (README, src, tests, eval if applicable).
2. Define the tool surface with zod schemas — types in code are the contract.
3. Add the MCP to the API gateway's host config so it's reachable.
4. Add the MCP to the Mac app's local MCP host bundle if the Mac app needs to call it directly.
5. Write contract tests covering each tool's happy path and at least one failure path.
6. Add an eval suite if the MCP affects output quality.
7. Update this file's per-server-spec section with the new MCP.
8. Update `PLAN.md` §6 with the high-level description and tool list.

Adding a new tool to an existing MCP is lighter — just add the schema, write the test, and update the README of that package.

## Anti-patterns (explicit "don't do this")

- **Cross-MCP calls inside an MCP.** MCPs do not call each other directly. The API gateway or the render-worker orchestrates multi-MCP flows. This rule keeps the dependency graph linear and avoids cyclic calls.
- **Side effects in `quote_*` tools.** Cost quotes are pure functions over the routing config and inputs. They never debit, never enqueue, never log billable events.
- **Inline secrets.** No API keys in the MCP source or env-var defaults. All secrets via Secrets Manager, fetched at startup.
- **HTTP calls outside the `pubfuse` MCP to Pubfuse.** Already covered in `AGENTS.md`; reiterating because it's the highest-risk leak point for code drift.
- **Long-running synchronous handlers.** Any tool that takes >30 seconds should split into an enqueue-and-poll pattern: the synchronous tool returns a job ID, the caller polls or subscribes to events. The Mac app and web both support SSE event streams from the gateway for this.
