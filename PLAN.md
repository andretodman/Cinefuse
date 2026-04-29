# Cinefuse — Unified Plan

This is the master plan. It is the single source of truth for what Cinefuse is, how it is built, and how it makes money. Cursor and Claude Code should both read this file end-to-end before proposing changes to the codebase. Other planning files (`MILESTONES.md`, `MONETIZATION.md`, `MCP-ARCHITECTURE.md`, `AGENTS.md`) elaborate on individual sections but do not contradict this document. If a contradiction is found, this document wins and the other files are updated.

## 1. Product vision

Cinefuse turns a short story idea into a finished short film. The user opens the Mac app, types or pastes a premise — for example, *"a lighthouse keeper discovers a stranded sea creature and must decide whether to return it to the ocean before a storm hits"* — and Cinefuse drafts a multi-scene script, generates a storyboard, locks the protagonist's appearance to a reference photo the user uploads, generates the clips with a chosen video model, composes a score and dialogue track, stitches everything onto a timeline, and exports a 3- to 8-minute short ready for upload to Pubfuse, YouTube, or wherever else the user wants it to live. The user sees and can edit every step. Generation is not magic; it is a guided pipeline with the user in the loop.

The reason Cinefuse exists is not that AI video models are new — they are not, in 2026 — but that the workflow of going from idea to finished film is still painfully fragmented. A typical solo creator today opens fal.ai, runs prompts in a playground, downloads MP4s, drags them into DaVinci Resolve, fights with audio in Logic, manually arranges the cuts, and gives up. Cinefuse compresses that loop into one app, with a Sparks-based pay-as-you-go model that maps cost to a single human-legible currency rather than seventeen API dashboards. Pubfuse already has the user accounts, file storage, streaming, and monetization rails; Cinefuse adds the creative pipeline on top.

The target user for v1 is a hobbyist creator or indie storyteller with a Mac, who wants to make 1–10 minute shorts to share with friends or build an audience. Secondary users include marketing and education professionals who need short narrative video without a production budget. The non-target user for v1 is the professional VFX artist; the floor we are raising is the *first watchable film*, not the *last 5% of polish*.

## 2. The product, end to end

A new user opens Cinefuse on macOS and signs in with their Pubfuse account (OAuth handoff via the Pubfuse SDK; if they don't have one, they sign up directly inside the app, which creates a Pubfuse user in the same flow). They land in the project gallery, where the seed projects we ship — "First Date Disaster," "The Lighthouse," "Office Heist" — are presented as templates. They pick "New project from prompt." They type a logline, set a target length (default 5 minutes), and pick a tone (drama, comedy, action, documentary, etc.). The Script MCP, backed by Claude, returns a beat sheet of 8–15 scenes, each with a one-paragraph description, suggested shots, and rough character list. The user reviews the beat sheet on the Storyboard tab, can rewrite any scene, and clicks Generate Storyboard. For each scene, the Script MCP produces 1–6 shot prompts; the user can edit them.

Before generating any video, the user defines the **cast**. The Character tab lists every named character in the script. For each one, the user uploads a reference photo (their own, a friend's, or an AI-generated portrait from Cinefuse's image generator). The Character MCP creates a per-character identity embedding using the Stand-In LoRA approach on top of Wan 2.x — a single reference is enough to lock face and broad style for short clips, and the user can supply 3–5 additional images for multi-angle robustness on hero characters. We are explicit with the user that *consistent characters across shots* is a core feature and a meaningful Sparks cost: each character training run is billed.

With cast and storyboard locked, the user goes shot by shot or batch-generates. For each shot, they pick a quality tier (Budget / Standard / Premium) and a reference character if applicable. The Sparks cost is shown before they click Generate. The Clip MCP routes to the appropriate model: Budget tier hits Wan 2.6 (~50 Sparks per 5s), Standard tier hits Kling 2.5 Turbo Pro (~70 Sparks per 5s), Premium tier hits Veo 3.1 with native audio (~250 Sparks per 5s for 720p with sound). The clip arrives in 30 seconds to 4 minutes depending on tier; the editor preview updates and the clip drops onto the timeline at its scene position.

The Audio tab handles dialogue and music. Dialogue uses ElevenLabs voice clones (one of the user's pre-cloned voices, or a default voice library) generated from the script's dialogue lines, with phoneme-aware lip-sync via Veo 3.1's native audio for premium-tier shots, or post-hoc Wav2Lip-style alignment on budget/standard shots. Score is generated via Suno or self-hosted MusicGen — the user picks a mood ("hopeful," "tense," "melancholic") and length, and the Audio MCP returns a clip. SFX comes from a curated stock library (Freesound CC0 tier) and a generative SFX endpoint for one-offs. The user mixes per-scene; the app does loudness normalization (-14 LUFS streaming standard) automatically on export. Production deployments configure real upstream adapters per tool (HTTP bridge and/or ElevenLabs + upload); the API gateway records structured skip diagnostics when a provider cannot fulfill a given audio feature without blocking the rest of the project pipeline.

The Stitch tab is the final-cut view. The Stitch MCP, running ffmpeg under the hood, assembles the timeline with optional cross-fades, dip-to-black transitions, and a basic color-match pass between adjacent clips so a Wan-generated sunset doesn't whiplash into a Kling-generated cool interior. The user can drag clips around, trim, swap takes, add captions (auto-generated via Whisper transcription of the dialogue track), and add title cards. When happy, they click Export. The Export MCP produces a 1080p H.264 MP4 (or 4K H.265 for premium subscribers), uploads it to Pubfuse Files, and optionally publishes it as a non-live "scheduled playback event" on the Pubfuse stream platform — meaning the user can share a Pubfuse URL where their movie plays for an audience.

Throughout, the user's Spark balance is visible in the toolbar. Running low triggers a non-modal nudge to top up via the App Store IAP sheet. Power users can subscribe to a Cinefuse Plus plan (monthly Sparks grant + 4K export + priority queue) directly through StoreKit auto-renewing subscriptions.

## 3. Platform choice

Cinefuse runs on **macOS** as a native SwiftUI app, with a **Next.js (React)** web app as the cloud platform and a **Node.js + Python** services tier for render orchestration. Long-form rationale follows; the short version is in the README.

The Mac native decision is forced by three converging requirements. First, Sparks IAP. The user explicitly wants App Store purchase to work; Apple's StoreKit 2 IAP API is only available to native binaries (and the WebKit IAP shim is not a substitute for purchasing consumable currency). A Tauri or Electron app cannot use StoreKit 2 directly. We could ship the Mac App Store build and a separate cross-platform free/paid build, but that doubles the binary maintenance for the smaller 30% of the early user base. Second, video performance. The editor needs frame-accurate scrubbing, multi-track preview, and waveform rendering on potentially-multi-minute timelines; AVFoundation gives this nearly free, while a Chromium-based desktop has to fight HTML5 video for the same thing and consume far more memory. Third, the Pubfuse SDK already has Swift patterns from the iOS implementation; porting iOS Swift code to a Mac SwiftUI target is a 1–2 week project, not a 1–2 month one.

The downside is that we ship Mac-only at launch. Windows is currently 70% of the global desktop OS share, but the *creator-with-an-M-chip-Mac* market is closer to 50/50 with Windows in the indie filmmaker segment, and the Mac App Store gives us a discoverability surface Windows lacks. We accept the trade. Phase 4 evaluates whether to ship a Tauri-wrapped Windows build (sharing the React web codebase) or a fully native Windows version.

The web app is required regardless of desktop platform. Pubfuse is a streaming platform; Cinefuse-produced movies are meant to be watched. We need a web playback URL per project, a public profile page per creator, and an account dashboard for billing history and Spark balance. The web app is built on Next.js for SSR-on-the-edge SEO benefits (creator profiles need to be indexable). The web app does *not* include the editor in v1 — that would force us to build the entire video pipeline twice. Web-as-editor is a Phase 5 question.

The render backend is a combination of Node.js (HTTP API gateway, MCP host, billing reconciliation, Pubfuse webhook handlers) and Python (model inference workers, ffmpeg orchestration, Whisper transcription). Node owns the request lifecycle; Python owns the heavy compute. They communicate over Redis-backed queues (BullMQ on Node, RQ or Celery on Python). This split is forced by the AI ecosystem — most video model SDKs and inference utilities are Python-native, and we don't want to wrap them in subprocess calls from Node when we can just have Python workers consume the queue directly.

## 4. Pubfuse integration strategy

Cinefuse lives on Pubfuse without modifying it. We register Cinefuse as a new SDK Client — Pubfuse already supports this; the docs describe each SDK Client operating in isolation with its own users, sessions, and data, with industry-standard API key authentication and optional HMAC signature verification. The Cinefuse client gets its own API key, HMAC secret, and isolated user space. A user who has a Pubfuse account from another property must explicitly opt into Cinefuse the first time they sign in (this is the SDK Client isolation contract; it cannot be bypassed and we should not try to). The signup flow on Cinefuse therefore creates a Pubfuse user *under the Cinefuse SDK Client*, and the user's Cinefuse identity is what the rest of the system uses.

The Pubfuse capabilities Cinefuse uses on day one are authentication (login, OAuth, password reset), user profiles (avatar, display name, bio), file management (upload generated MP4s, fetch back via the public file endpoint for sharing), and streaming for the share-to-community feature (a finished movie can be scheduled as a non-live playback event). The Sparks balance is stored on the Pubfuse user record. Per the spec, in v1 the balance is hard-coded to a generous amount (proposed: 100,000 Sparks per new user) so the team can validate the full creative loop before billing is wired in. The schema is designed so that flipping IAP on in M6 is a single subsystem change, not a refactor.

What Cinefuse does *not* use from Pubfuse on day one is LiveKit streaming for live broadcasts (we don't broadcast anything during creation), the chat WebSocket (no chat in the editor), and tokens/diamonds (those are the live-streaming gift currencies; Sparks are conceptually distinct and have a separate ledger). These remain available for Phase 5+ features such as live "watch parties" for Cinefuse premieres.

The eventual extension of Pubfuse — once the Cinefuse-specific endpoints prove out — adds a small set of endpoints to the Pubfuse REST API:

- `POST /api/v1/cinefuse/projects` — create a film project (title, owner, settings, current state)
- `GET /api/v1/cinefuse/projects` — list projects for the authenticated user
- `GET /api/v1/cinefuse/projects/{id}` and `PUT /api/v1/cinefuse/projects/{id}` — read and update project structure (scenes, shots, characters, audio tracks)
- `POST /api/v1/cinefuse/projects/{id}/shots` and `GET /api/v1/cinefuse/projects/{id}/shots` — create/list shot records
- `POST /api/v1/cinefuse/projects/{id}/jobs` and `GET /api/v1/cinefuse/projects/{id}/jobs` — create/list render jobs
- `POST /api/v1/cinefuse/sparks/debit` and `POST /api/v1/cinefuse/sparks/credit` — Spark ledger operations, idempotent
- `POST /api/v1/cinefuse/sparks/iap-redeem` — redeem an Apple StoreKit transaction for Sparks; server validates the receipt with Apple

These endpoints initially live in the Cinefuse cloud backend talking to Pubfuse for auth and file ops. Once they stabilize (post-M6), they migrate into Pubfuse proper so future Pubfuse SDK Clients (other apps your company or partners build) get a project/job/sparks system for free. This is the "extend Pubfuse so any new app benefits" goal from the spec, but staged so we don't block on it.

The HMAC-signed webhook surface from Pubfuse is used in two places. Pubfuse pings Cinefuse on user deletion (so we can drop their projects per data-retention policy) and on file upload completion (so the editor knows when a generated clip is durably stored). Cinefuse pings Pubfuse on Spark debit and on render completion (so future Pubfuse-side dashboards can show Cinefuse activity). HMAC verification is mandatory in both directions; nothing is trusted on hostname alone.

## 5. The video pipeline

The pipeline has six stages. Each stage is owned by one MCP server, has a clean input/output contract, and can be re-run idempotently — re-rendering a single scene's clip should never invalidate the rest of the project.

**Stage 1: Script.** Input is a logline, target length, tone, and optional reference scripts. Output is a structured beat sheet of scenes, with per-scene description, location, characters present, mood, and proposed shot list. The Script MCP wraps Claude (via the Anthropic API) with a carefully versioned system prompt for screenplay structure, and exposes both `generate_beat_sheet` and `generate_shot_prompts` tools. We treat scripts as the project's source of truth for narrative; everything downstream (clip prompts, audio cues, captions) derives from the script. Storing the script as structured JSON rather than free text is a deliberate choice — it lets us programmatically swap a character's name everywhere, regenerate a single scene without re-running others, and compute Sparks-cost estimates accurately.

**Stage 2: Character lock.** Input is a character name, reference image(s), and an optional per-character style note. Output is a character record with an identity embedding, a Stand-In LoRA reference (or per-shot IP-Adapter conditioning, depending on the target model), and a sample preview image. The recommended primary technique is Stand-In LoRA on Wan 2.1, a character-consistency adapter trained to lock identity from a single image, applied at model load to ensure the identity signal is fused at the foundation. For non-Wan models we fall back to per-shot IP-Adapter face conditioning. We also research and integrate Kling 3.0's multi-shot capability of 3-15 seconds with subject consistency across different camera angles for premium tier — for these shots, character lock is delegated to the model's native consistency feature rather than to our own LoRA. The Character MCP abstracts this so the editor doesn't care which mechanism is in use.

**Stage 3: Clip generation.** Input is a shot prompt, target duration (3–10 seconds), tier (Budget/Standard/Premium), optional character lock(s), optional starting/ending image (for image-to-video shots), and optional motion control reference. Output is an MP4 plus a thumbnail and metadata (model used, seed, actual duration, Sparks cost). The Clip MCP routes:

- Budget tier → fal.ai endpoint for Wan 2.6 or LTX-2 (~$0.04–$0.08/sec floor cost)
- Standard tier → fal.ai endpoint for Kling 2.5 Turbo Pro (~$0.07/sec) or Hailuo 2.3 Pro (flat $0.49/clip)
- Premium tier → fal.ai endpoint for Veo 3.1 with audio (~$0.40/sec), Sora 2 Pro for narrative shots (~$0.30–$0.50/sec), or Kling 3.0 Pro for multi-shot sequences

Routing is in code, not in user-visible UI — the user picks a tier, we pick the best model for the shot type within that tier. We optimize for variety: if the user picks Standard for a dialogue scene we send to Kling because of its strong motion fluidity; if it's an establishing shot we may send to Wan 2.6 Pro or Hailuo because they're strong at landscape and product cinematics. The model registry is data-driven (a YAML config in the Clip MCP repo); adding a new model is a config change plus a small adapter, not a refactor.

**Stage 4: Audio.** Input is a scene's dialogue lines (with speaker IDs), a mood/intent for score, and an optional list of SFX cues. Output is a multi-track WAV (dialogue, score, SFX) plus a mixdown. Dialogue uses ElevenLabs by default (excellent voice cloning quality, well-known API; costs ~$0.18–$0.30 per minute of speech depending on plan tier — budget into Sparks at ~10 Sparks per spoken second). Score uses Suno API (~$0.10–$0.30 per 30-second piece) for Standard tier and self-hosted MusicGen for Budget tier. SFX is a static library (Freesound CC0) plus a generative endpoint (Stable Audio Open or AudioGen) for one-offs. Lip-sync for premium tier is delegated to Veo 3.1's native audio + lipsync; for budget/standard tiers we run Wav2Lip or a similar post-process to align mouth movement to dialogue.

**Stage 5: Stitch.** Input is the project's timeline (scene order, per-scene clip URLs and audio tracks, transition specs, color grade hints, captions). Output is a single composited MP4 ready for export. The Stitch MCP shells out to ffmpeg via well-tested filtergraphs. Cross-fades and dip-to-black are standard ffmpeg `xfade` filters. A lightweight color-match pass uses ffmpeg's `colormatrix` and a histogram-equalization step between adjacent clips to reduce the "AI cut" feel where one clip is markedly bluer than the next. Captions are baked in optionally — by default they live in a separate VTT track for accessibility but get hard-burned on export if the user toggles "Open Captions." Loudness normalization to -14 LUFS is automatic.

**Stage 6: Export.** Input is the stitched MP4 and per-project export settings (resolution, codec, container, captions on/off). Output is the final deliverable file uploaded to Pubfuse Files, with a sharable URL, optional Pubfuse stream publication, and optional direct upload to YouTube/Vimeo (via the user's connected accounts; OAuth handled at the cloud-platform layer). The Export MCP also writes a project archive — the script JSON, all clip MP4s, all audio tracks, and a manifest — into Pubfuse Files so users can re-edit later or migrate the project off-platform. We are explicit in our terms that the user owns their generated content and can take it with them.

## 6. MCP architecture

The system is composed of eight MCP servers. Each is a separate package in a monorepo (`/mcp/<name>`), with its own tool surface, dependencies, and tests. The Mac app, the cloud backend, Cursor, and Claude Code all consume these MCPs over the standard MCP transport. For the Mac app this means the SwiftUI client speaks MCP-over-stdio to a local MCP host process that bundles the MCP servers it needs in-process; the cloud backend runs each MCP as its own service behind the Node API gateway. Full per-server specs are in `MCP-ARCHITECTURE.md`.

The eight servers and their headline tools:

`pubfuse` — wraps Pubfuse REST. Tools: `get_user`, `update_profile`, `list_files`, `upload_file`, `get_file_url`, `create_scheduled_event`, `get_spark_balance`, `verify_webhook_hmac`. This is the only MCP that talks to Pubfuse over HTTP; everyone else talks to Pubfuse via this MCP. That gives us one place to update if Pubfuse's API evolves.

`billing` — owns the Spark ledger. Tools: `quote_cost` (preview cost for an action), `debit` (atomic with idempotency key), `credit`, `get_balance`, `redeem_iap_receipt`, `list_transactions`. Backed by Postgres. Every other MCP that costs Sparks calls `billing.quote_cost` before doing work and `billing.debit` after — never the other way around, and never directly inside another MCP's logic.

`script` — script and storyboard generation. Tools: `generate_beat_sheet`, `revise_scene`, `generate_shot_prompts`, `extract_characters`, `extract_dialogue`, `revise_dialogue`. Wraps Claude API. All output is structured JSON; no free-text screenplay format until export.

`character` — character identity management. Tools: `create_character`, `train_identity` (uploads ref images, runs LoRA training for hero characters), `embed_identity` (lightweight embedding for bit characters), `list_characters`, `delete_character`, `preview_character` (generate a sample frame to verify identity). Uses Stand-In LoRA on Wan 2.x as primary; IP-Adapter as fallback.

`clip` — video clip generation. Tools: `quote_clip` (returns Sparks cost without generating), `generate_clip` (text-to-video or image-to-video), `regenerate_clip` (same prompt, new seed), `list_models` (reports the available routes per tier). Uses fal.ai as the primary inference provider in Phase 1–2; routes to self-hosted Wan 2.2 in Phase 3 for budget tier.

`audio` — dialogue, score, SFX, mixing. Tools: `generate_dialogue` (TTS via ElevenLabs), `generate_score` (Suno or MusicGen), `lookup_sfx` (search the static library), `generate_sfx` (Stable Audio), `mix_scene` (returns a mixed scene track), `lipsync` (post-process for non-Veo clips). The mix is done in Python with `pydub` for the master and `ffmpeg` for any sample-rate or codec conversion.

`stitch` — timeline assembly. Tools: `preview_stitch` (low-res draft for the editor), `final_stitch` (full-res), `apply_transitions`, `color_match`, `bake_captions`, `loudness_normalize`. Pure ffmpeg work; no models. Critical that this is fast and predictable since it runs many times per project.

`export` — final encode and distribution. Tools: `encode_final` (1080p/4K, H.264/H.265), `upload_to_pubfuse`, `publish_to_pubfuse_stream`, `archive_project` (creates the re-editable bundle), `connect_youtube` / `connect_vimeo` (OAuth flows for direct upload). Per-export Sparks cost is small (covers encode + storage); the meaningful cost was in clip generation upstream.

Adding a new feature follows one of two patterns. New capability that fits in an existing MCP (for example, a new transition style) is a new tool on the `stitch` server. New capability that is its own bounded domain (for example, an "asset library" for stock footage purchase) is a new MCP server. Either way, both Cursor and Claude Code can introspect the MCP and start using its tools immediately, because the tool descriptions are the documentation. This is the leverage of going MCP-first: we never have to write a separate "how to call this internal service from an LLM" doc; the MCP schema *is* the doc.

## 7. Repository and build layout

A single monorepo, `cinefuse/`, with the following top-level structure:

```
cinefuse/
├── README.md                   # this planning bundle copied in
├── PLAN.md
├── AGENTS.md
├── MILESTONES.md
├── MONETIZATION.md
├── MCP-ARCHITECTURE.md
├── apps/
│   ├── mac/                    # SwiftUI macOS app, Xcode project
│   ├── web/                    # Next.js public site + creator dashboard
│   └── ios/                    # Phase 4 iOS app, shares SwiftUI views
├── mcp/
│   ├── pubfuse/
│   ├── billing/
│   ├── script/
│   ├── character/
│   ├── clip/
│   ├── audio/
│   ├── stitch/
│   └── export/
├── services/
│   ├── api-gateway/            # Node.js, Express/Fastify, MCP host
│   ├── render-worker/          # Python, BullMQ consumer, ffmpeg
│   └── webhook-receiver/       # Node.js, Pubfuse + Apple webhook handler
├── packages/
│   ├── shared-types/           # TypeScript types shared across web + Node services
│   ├── sparks-sdk/             # Thin Pubfuse REST client wrapper, used by Node services
│   └── ui-tokens/              # Shared design tokens for Mac (Swift) and Web (CSS)
├── infra/
│   ├── terraform/              # AWS infra: ECS, RDS, S3 (or Pubfuse-managed), Redis
│   ├── docker/
│   └── github-actions/
└── tools/
    ├── scripts/
    └── eval/                   # Eval harness for clip/audio/script quality
```

The Mac app is the only non-Node/non-Python piece. It speaks to MCPs via a local host bundled in the app, and to the cloud over plain HTTPS to the Node API gateway. The cloud's API gateway is the only thing that holds long-lived secrets (fal.ai keys, ElevenLabs keys, etc.) — those never ship inside the Mac binary. The Mac app's authority to use them is mediated by the user's Pubfuse session token plus an HMAC-signed request envelope.

Build orchestration uses Turborepo or Nx for the JS/TS side and Swift Package Manager for the Mac side. CI runs in GitHub Actions: per-package tests on every PR, integration tests gated to a labeled PR, end-to-end tests on `main`. Deployment is GitHub Actions → ECR/ECS for services, App Store Connect for the Mac app (manual release after TestFlight beta).

## 8. Data model essentials

The minimum entities the cloud needs to reason about, with their owners:

`User` — owned by Pubfuse. Cinefuse stores a thin profile cache keyed by Pubfuse user ID for performance, refreshed on login.

`Project` — owned by Cinefuse. Fields: id, owner_user_id, title, logline, target_duration, tone, created_at, updated_at, current_phase (script | storyboard | character | clip | audio | stitch | export | done), thumbnail_url, archive_url, total_sparks_spent. The phase field drives the Mac app's wizard-style navigation but does not gate access to other phases.

`Scene` — owned by Cinefuse. Belongs to a Project. Fields: id, project_id, order_index, title, description, location, mood, duration_target, characters (array of Character IDs), created_at, updated_at.

`Shot` — owned by Cinefuse. Belongs to a Scene. Fields: id, scene_id, order_index, prompt, model_tier, model_id (after generation), duration, character_locks (array), starting_image_url, clip_url, thumbnail_url, sparks_cost, status (draft | queued | generating | ready | failed), seed, created_at, updated_at.

`Character` — owned by Cinefuse. Belongs to a Project. Fields: id, project_id, name, description, reference_image_urls, identity_embedding_id, lora_url (if hero), preview_url, created_at, updated_at. Hero characters (those with a trained LoRA) cost more Sparks to create but are reusable across many shots within a project; bit characters use IP-Adapter conditioning per shot.

`AudioTrack` — owned by Cinefuse. Belongs to a Scene. Fields: id, scene_id, kind (dialogue | score | sfx), source (generated | uploaded | library), source_ref, duration, mixed_url, created_at.

`SparkTransaction` — owned by Cinefuse, mirrored to Pubfuse. Fields: id, user_id, kind (debit | credit | iap_redeem), amount, idempotency_key, related_resource_type, related_resource_id, balance_after, created_at, apple_transaction_id (nullable, for IAP). The ledger is append-only.

`RenderJob` — owned by Cinefuse. Fields: id, user_id, project_id, kind (clip | audio | stitch | export), input_payload (JSON), output_payload (JSON), status (queued | running | done | failed), started_at, completed_at, sparks_quoted, sparks_charged, model_used, cost_to_us_cents (for finance reconciliation), retry_count.

The `cost_to_us_cents` field on `RenderJob` is critical for unit economics. We store what we actually paid the upstream provider for every generation. Finance can compute live gross margin per tier, per model, per user cohort. Without this, pricing is guesswork.

## 9. Security and abuse

Authentication is Pubfuse-managed. Cinefuse never stores user passwords. Session tokens from the Pubfuse SDK are passed to the Cinefuse cloud as bearer tokens; the cloud validates them against Pubfuse on every request (with a short-lived cache to avoid DDoS-ing Pubfuse's auth endpoint).

Secrets management: fal.ai, ElevenLabs, Suno, Anthropic, Apple StoreKit verification keys all live in AWS Secrets Manager (or Pubfuse's equivalent if they offer one), accessed by the API gateway only. The Mac app has no API keys for any third party.

IAP receipts are validated server-side against Apple's verification endpoint before Sparks are credited. Receipts are stored to prevent double-redemption. A user who refunds an IAP through Apple gets their Sparks reversed via `billing.credit` with a negative amount once the refund webhook fires.

Abuse prevention has three layers. First, content policy at the prompt layer: the Script MCP and the Clip MCP both run safety filters on user prompts, refusing public-figure naming, minor sexualization, weapon-glorification, and other forbidden categories. Second, rate-limiting at the API gateway: per-user concurrent jobs cap (default 3 budget, 1 premium), per-IP request rate cap, anomaly detection on Sparks spend velocity (sudden 10x surge triggers a soft hold). Third, model-side moderation: all upstream providers (fal.ai, ElevenLabs, Veo) have their own content policies; we surface their refusals to the user with clear messaging rather than retrying with bypasses.

Render outputs are scanned for known-bad content (CSAM hash database, public-figure face matching for the top 1000 most-mimicked figures) before being returned to the user. A flagged output is held, the user is shown a generic "this generation could not complete due to our content policy" message, and a moderator reviews. False positives get hand-released within 24h SLA.

User-uploaded reference images go through the same scan. We do not allow users to upload images of identifiable real public figures as character references.

## 10. Content and ethics policy

Cinefuse is a creative tool used by many people, some of whom will try to misuse it. The policy must be public, specific, and enforced consistently.

Prohibited generations: any sexual content involving minors; non-consensual sexual content involving identifiable real people; content depicting graphic real-world violence against identifiable real people; content that incites imminent violence; CSAM in any form; weapons-of-mass-destruction synthesis instructions packaged as "movies"; deepfake content of public figures presented as real news. These are hard refusals at the prompt layer and at the output-scan layer.

Restricted but allowed: fictional violence including death, in service of narrative (with clear fictional framing); romantic and tasteful sexual content between unambiguously adult characters (off by default; opt-in adult mode is a Phase 3+ feature, not v1); political satire of public figures (allowed with a clear "satire" watermark and a per-export disclosure); horror content within mainstream theatrical norms.

Always allowed and encouraged: original characters of any kind; the user's own likeness (after explicit confirmation that they own the rights); fictional violence with cartoon framing; documentary-style narrative; instructional content; family content; fantasy and science fiction; LGBTQ+ stories; stories about underrepresented communities (this is a feature, not a flag).

Watermarking. All Cinefuse-generated content embeds a C2PA content credential at export, identifying the work as AI-generated and listing the upstream models used. Users can opt out for premium-tier projects but the C2PA presence is the default. The watermark is invisible to viewers but machine-detectable, and we comply with regional AI-content-disclosure laws (EU AI Act Article 50 in particular).

User likeness rights. Users uploading their own face must check a consent box. Users uploading another person's face must check a consent box certifying they have that person's permission. We do not enforce this beyond the contractual layer in v1, but Phase 3 adds optional liveness-check-style ID verification for users who want to publish under a "verified author" badge.

## 11. Observability and quality

Every render job emits structured events to a logging pipeline (CloudWatch + a Postgres aggregate table for fast queries). Per job we capture: latency p50/p95/p99, queue wait, provider, cost, output quality score (where computable), user-rated quality (after the user accepts or rejects the output). This data drives the routing logic — if Kling's p95 latency on dialogue shots exceeds 90 seconds for a sustained period, we automatically deprioritize it for that shot type in the Standard tier.

Quality is measured automatically and manually. Automatically, we run CLIP-similarity between the prompt and a sampled frame from each clip, and we run face-similarity between character reference images and detected faces in clips for character-locked shots. Below-threshold outputs are surfaced to the user with a "regenerate free" offer (Sparks refunded). Manually, a 1% sample of outputs from each model is reviewed weekly by an internal quality team (initially the founders) using a rubric — temporal coherence, prompt adherence, character consistency, audio-video sync. Manual scores feed a model-per-tier leaderboard that determines the routing config.

Eval harness lives in `/tools/eval/`. It is a fixed set of ~50 representative prompts spanning genres, character counts, locations, and shot types. Each MCP that affects quality (`script`, `character`, `clip`, `audio`, `stitch`) has its own eval suite. Running the suite is a CI-gated step on any PR that touches generation logic.

## 12. Why this can realistically make money

The unit economics work in our favor for one reason: clip generation has a real, computed cost per second, and we can charge a healthy margin on top because the user is paying for *the loop being collapsed*, not for the bits. A user generating 30 seconds of standard-tier video pays us ~420 Sparks ($4.20 effective); we pay fal.ai ~$2.10 for the underlying generation. Layer on script (Claude API, ~$0.01 per scene), audio (~$0.30/minute speech + ~$0.20/minute music), and storage (negligible per project), and a typical 5-minute short costs us $30–$60 in COGS at standard tier. We charge the user roughly $90–$180 in Sparks. That is a 50–60% gross margin on the average project, before factoring in the subscriber base who pay flat fees.

The defensible part is not the underlying models — those are commodities, and Wan/Kling/Veo will each be replaced by something better in 6 months. The defensible part is the workflow on top: the script → storyboard → character → clip → audio → stitch loop, the project archive format, the share-to-Pubfuse community surface, the Sparks economy that means users don't have to hold a fal.ai account, and the Mac-native editor experience. None of those are individually unique; together they're a moat against a casual entrant.

Realistic Year 1 revenue scenarios are detailed in `MONETIZATION.md`. The bear case (5,000 paying users at $15/mo average) is $900K ARR. The bull case (50,000 paying users at $25/mo average from a successful App Store featuring) is $15M ARR. Both are achievable within the Mac-creator TAM; both depend on the App Store discovery flywheel that comes from a polished v1.

## 13. Risks and how we'll know they're materializing

The biggest single risk is **model API price volatility**. fal.ai's prices can shift; Veo's prices have already shifted twice in 2025–2026. We mitigate by storing `cost_to_us_cents` per job and recomputing Spark conversion rates monthly behind a feature flag — if a cost shock hits, we adjust the Sparks price for that tier within 48 hours. The covenant with users is that *Sparks already in their balance* don't lose purchasing power suddenly; instead, future top-ups buy fewer/more Sparks. This is the same mechanism used by airline miles, well-understood by users.

The second risk is **App Store rejection on AI content grounds**. Apple has been inconsistent about generative AI apps. Mitigation: a thorough safety brief in the App Review submission, age-gate on adult mode (when shipped), demonstrable C2PA watermarking, explicit content policy linked from the app's main menu. Worst case, we ship outside the Mac App Store via Sparkle auto-update with web-based Spark purchase (Stripe) and lose the discovery surface — survivable but painful.

The third risk is **a competing product from a giant**. Apple Final Cut Pro could add Genmoji-style scene generation; Adobe could ship something inside Premiere; Runway is one acquisition away from doing exactly this. Our edge is speed-to-MVP and the Pubfuse integration. We need M5 (a complete creative loop) shipped within 20 weeks of M0 to establish category presence before anyone else gets there.

The fourth risk is **character consistency not being good enough**. Stand-In LoRA on Wan 2.x is the current best open approach, but consistency across 30+ shots in the same film is still an unsolved problem at the time of writing. If our M3 character system can't deliver convincing lock across, say, 80% of generated shots in eval, we have to scope the v1 product to "shorter films with stylized characters" rather than "feature-quality narrative." This shapes marketing copy, not the architecture; the architecture handles either reality.

The fifth risk is **quality variance frustrating users**. Generative video sometimes whiffs. Our defense is the regenerate-free-on-failure policy — if our quality scorer flags a clip below threshold, the user gets a free re-roll. This costs us COGS we can't pass on, but it's the only way to keep users from feeling cheated by Sparks spent on a bad output.

## 14. The next two weeks

Before any code is written, the founder's open questions in README.md must be answered. After that, M0 starts with: provisioning the Pubfuse SDK Client, scaffolding the monorepo and the eight MCPs as empty stubs with contract tests, hooking up CI, building the Mac-app login screen against the Pubfuse SDK, and sending a single hand-built ledger event to validate the billing flow end to end. M0 success is a Mac app that signs a user in, shows their Spark balance (hard-coded 100,000), and lets them create an empty project record in the cloud. That is small, but it lights up every component once and proves the architecture before we start filling in the expensive parts.

Beyond M0, follow `MILESTONES.md`. Beyond the milestones, follow the daily rhythm in `AGENTS.md`. And whenever a decision needs to be made that this plan does not cover, write it down here and update everything downstream.
