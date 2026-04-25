# MILESTONES.md — Cinefuse delivery plan

This is a 27-week plan to public beta. The shape is six creative-loop milestones (M0–M5), then commerce (M6), then beta and growth (M7–M8). Each milestone has acceptance criteria; the milestone is "done" when those criteria are demonstrably met, not when calendar time runs out. If a milestone slips, milestones downstream slip with it; we do not move M2 forward by skipping M1's acceptance.

The plan assumes a small team — three to five engineers (one Mac/Swift, two backend/MCP, one frontend/web, optional one ML/eval) plus design and PM support. A larger team can compress the schedule but cannot skip the dependency order.

## M0 — Foundations (weeks 1–3)

The goal of M0 is to prove the architecture without spending money on generation. Everything is real *plumbing* with hard-coded mock generation results.

What gets built: monorepo scaffolded with all eight MCP stub servers, API gateway, render-worker, webhook-receiver. The Mac app shows a login screen, completes Pubfuse OAuth, lands on a project gallery, and lets the user create an empty project. The cloud persists projects to Postgres. The `pubfuse` MCP wraps a minimal slice of Pubfuse's REST (auth, profile read, file upload mock). The `billing` MCP exposes `get_balance` returning the hard-coded 100,000 Sparks. CI is green on every PR. Terraform deploys a dev environment to AWS (or wherever Pubfuse hosts; align with Pubfuse's infra in M0 week 1).

Acceptance: a fresh-cloned developer machine can run `make bootstrap && make dev` and reach a working Mac app + cloud + MCPs locally within 20 minutes. A new user can sign up, see their 100,000 Spark balance, and create a project that persists across app restarts. All eight MCP stubs respond to a `list_tools` introspection call. CI runs unit tests, lints, and a contract-test suite for every MCP, all green. The Pubfuse SDK Client is provisioned and its keys are in Secrets Manager.

What is *not* in M0: any actual generation, the script tab, the storyboard tab, the character tab, audio, stitch, export, IAP. Just plumbing.

## M1 — Clip generation (weeks 4–7)

The first user-visible feature with real cost. The user creates a project, types a single shot prompt, picks a tier, sees the Spark cost, confirms, and gets back a generated MP4 ~30s–4min later.

What gets built: the `clip` MCP wired to fal.ai for Wan 2.6 (Budget) and Kling 2.5 Turbo Pro (Standard). Premium tier is stubbed for M1. The Mac app gains a Shots tab on a project — a flat list view, no storyboard yet. Each shot row shows the prompt input, tier picker, cost preview, generate button, and resulting clip with a thumbnail and AVPlayer preview. The render-worker picks up generation jobs from a Redis queue, calls fal.ai, downloads the resulting MP4 to Pubfuse Files via the `pubfuse` MCP, updates the job row, and notifies the API gateway via SSE. The `billing` MCP starts actually debiting Sparks (still on hard-coded balances).

Acceptance: a user can generate at least 50 clips end-to-end without intervention, with a documented Sparks cost per clip that matches the routing table in `MONETIZATION.md` within 2%. The `cost_to_us_cents` field is populated for every job and a finance dashboard query (raw SQL is fine in M1) computes gross margin per tier per day. Failed generations refund Sparks via `billing.credit` automatically. Internal eval harness has a 50-prompt baseline run published; quality scores are within expected bands per tier.

The big risk in M1 is fal.ai integration weirdness — undocumented edge cases in their async API, rate limits we don't know about, output formats that don't match what we expect. Build defensively, log everything, and budget two days of M1 explicitly for "fal.ai surprised us" debugging.

## M2 — Script and storyboard (weeks 8–10)

Now the user can start from an idea, not a prompt. The Script MCP turns a logline into a multi-scene beat sheet, and a storyboard view shows it.

What gets built: `script` MCP with `generate_beat_sheet`, `revise_scene`, `generate_shot_prompts`, `extract_characters`, `extract_dialogue` tools. Wraps the Anthropic API. The Mac app gets a New Project from Prompt flow, then a Story tab showing the beat sheet (editable scene cards), and a Storyboard tab showing per-scene shots (each shot is a row with a prompt; clicking generate goes through M1's path). The user can save the project and resume later.

Acceptance: a user gives a 1-sentence logline and a target duration; within 60 seconds the system has produced a beat sheet of 8–15 scenes, each with description, characters, mood, and 2–6 shot prompts. The user can edit any field, regenerate any scene, and the changes persist. A 5-minute target produces a beat sheet that, when fully generated at standard tier, would cost the user roughly 1,500–2,500 Sparks (this becomes the benchmark used in marketing copy: "a 5-minute short for ~$20 in Sparks").

What's still rough in M2: characters are just names with no consistency between shots. Audio doesn't exist yet. Stitch is manual. M2 is the "I made a 5-minute incoherent slideshow" milestone — exciting but not finished.

## M3 — Character consistency (weeks 11–14)

The hardest technical milestone. Characters look the same across shots.

What gets built: `character` MCP with `create_character`, `train_identity`, `embed_identity`, `preview_character` tools. Stand-In LoRA training pipeline on Wan 2.x for hero characters (~3–5 minutes of GPU time per character). IP-Adapter conditioning fallback for bit characters (no training, applied per-shot). The Character tab in the Mac app: drop in a reference photo (or generate one with a built-in image model), name the character, click Train. Characters are then selectable on each shot in the Storyboard.

Acceptance: in the eval harness, character lock works on at least 80% of generated shots when a hero character is used (defined as: face-similarity >0.7 against the reference, on a 0–1 scale, in a frame sampled mid-clip). Bit characters (IP-Adapter) work on at least 60% of shots. The character training cost is correctly debited in Sparks (~500 Sparks per hero character feels right; finalize during M3 week 1 based on actual GPU time observed). The user can re-use characters across multiple shots without re-training.

The primary risk is that 80% lock rate isn't achievable with current open techniques. If eval at week 13 shows we're stuck at 60–70%, we have two responses: tighten the v1 marketing claim ("strong character consistency in stylized scenes; results vary in photorealistic complex scenes") and ship with the warning, or delay M3 by 2–3 weeks while we evaluate Kling 3.0's native multi-shot consistency for premium tier (already documented as supporting subject consistency across camera angles, per the source research in `PLAN.md`). Either is acceptable; pretending the problem is solved when it isn't is not.

## M4 — Audio (weeks 15–17)

Movies need sound. M4 wires up dialogue, score, and SFX.

What gets built: `audio` MCP with `generate_dialogue` (ElevenLabs), `generate_score` (Suno for Standard, MusicGen self-hosted for Budget), `lookup_sfx` (static library lookup), `generate_sfx` (Stable Audio), `mix_scene`, and `lipsync` (post-process Wav2Lip-style for non-Veo clips). The Audio tab in the Mac app: per-scene editor showing the script's dialogue lines, voice picker per character, mood picker for score, drag-in SFX from a library palette. Mix preview using AVFoundation. Lipsync runs as a post-render job, not blocking the user.

Acceptance: a user can generate dialogue audio for a 5-minute project, score for each scene, and SFX for major beats, with all three mixed correctly to -14 LUFS at scene level. ElevenLabs voice quality on dialogue is rated 4/5 or better in internal review. Lip-sync drift on non-Veo clips is under 100ms median, under 200ms worst-case (in a 30-clip eval). Sparks cost for audio on a typical 5-minute project lands at ~10–15% of the project's total Sparks spend.

What's still missing: stitching is still manual file-juggling; the user has audio and clips but has to assemble them in some external tool to see the finished movie.

## M5 — Stitch and export (weeks 18–20)

The end of the creative loop. The user gets a finished, watchable, exportable movie.

What gets built: `stitch` MCP (`preview_stitch`, `final_stitch`, `apply_transitions`, `color_match`, `bake_captions`, `loudness_normalize`). `export` MCP (`encode_final`, `upload_to_pubfuse`, `publish_to_pubfuse_stream`, `archive_project`, optional YouTube/Vimeo OAuth flows). The Mac app gets a Stitch tab — a true timeline view, drag-to-reorder, trim handles, transition pickers between adjacent clips, captions toggle. An Export modal lets the user pick resolution (1080p / 4K), captions on/off, and target (Pubfuse / YouTube / file download).

Acceptance: a user can take a project from logline to finished MP4 entirely inside Cinefuse, with no external tool, in under 4 hours of human time (excluding generation wait time) for a 5-minute short. The exported file plays correctly in Quicktime, VLC, on iOS, on Pubfuse's web player. Captions are accurate to the script's dialogue (Whisper transcription accuracy >95%). Color-match between adjacent clips reduces the visible "AI cut" in 80% of clip pairs in eval. C2PA watermark is embedded in every export.

This is the milestone where the product is *real*. Everything before this is interesting demo; M5 is when someone could actually use Cinefuse to make a thing they care about.

## M6 — IAP and live billing (weeks 21–23)

Money flows.

What gets built: StoreKit 2 IAP integration in the Mac app for Spark packs (5 SKUs covering $4.99 to $99.99 — see `MONETIZATION.md`). Apple receipt validation server-side via the `billing` MCP's `redeem_iap_receipt` tool. Subscription products for Cinefuse Plus monthly and annual, with auto-renewal handling, refund webhooks, family sharing. The hard-coded 100,000 Sparks balance flips to a real ledger; new users start with a generous-but-finite welcome grant (proposed: 2,500 Sparks, enough for a 1-minute experiment). The Mac app's Spark balance widget gets a "+" button that opens StoreKit's IAP sheet inline.

Acceptance: a user can buy Sparks via StoreKit, see them appear in their balance within 5 seconds, and generate a clip with the new balance. Refunds via Apple subtract Sparks from the balance correctly (negative going to zero, never negative). Subscription auto-renewal credits Sparks on the renewal date via the Apple notification webhook. App Store Connect IAP products are configured and Apple has reviewed/approved at least one Spark pack SKU.

The risk in M6 is Apple. App Store IAP review can be slow and capricious. Submit the first SKU configurations in M5 if possible to absorb review time in parallel. Have a Stripe-based Spark purchase path ready (web only, never inside the app) as a backup for the case where the App Store version is delayed past M7.

## M7 — Public beta (weeks 24–26)

Polish, fill the rough edges, and let real users in.

What gets built: a real onboarding flow (welcome → sample project tour → first shot generation → save project), three sample projects shipped with the app, marketing site at cinefuse.com, pricing page, support page, terms and privacy, a feedback button that opens a structured form. App Store Connect listing complete: screenshots, video preview, app description, keywords. TestFlight beta opens to ~500 users from a wait-list collected during M2–M6.

Acceptance: NPS from beta users >30. At least 50 finished movies (full export) made by users who are not Cinefuse staff, posted publicly somewhere (Pubfuse community, YouTube, social). Apple App Store submission accepted (note: not necessarily released — featured release timing is its own thing). Crash-free session rate >99%. Average time-to-first-export under 3 hours (a beta user can sign up and have a finished short same day).

This is the milestone where the marketing and the product have to match. If the product still feels rough at M7, push back the App Store submission rather than ship a poor first impression. Reputation in App Store discovery comes from the first 1,000 reviews.

## M8 — GA and growth (week 27+)

Beta is over. Cinefuse is for sale.

What gets built: Phase 3 self-hosted Wan 2.2 cluster on H100s for the Budget tier — drops our COGS on the most price-sensitive tier from ~$0.05/sec to ~$0.02/sec, expanding margin or letting us undercut competitors. iOS preview app (read-only viewer for projects, no editor; share-to-friend flow on mobile). Web preview-only viewer at `cinefuse.com/v/<project-id>`. Referral program (give 500 Sparks, get 500 Sparks). Initial paid acquisition tests on TikTok/Instagram targeting indie filmmaker audiences.

This phase is open-ended and depends on what the data shows from M7. Possible directions: a "remix" feature letting users fork a public project, an integrated voice-actor marketplace (real humans paid in Sparks for premium voice work), live "watch parties" using Pubfuse's existing LiveKit streaming. Choose based on user behavior, not roadmap inertia.

Acceptance for M8 is not a single deliverable. It's the steady-state metrics the business depends on: 30-day retention >25%, paying-user fraction of monthly active >8%, gross margin >50%, App Store rating >4.4, weekly active project creators growing month over month. Hit those, and Cinefuse is a real business.

## What slips first when reality intervenes

Reality always intervenes. Here is the priority order for what to cut if a milestone is at risk:

First to cut: **scope within a milestone**, not the milestone itself. M3 with 70% character lock instead of 80% still ships; we adjust marketing copy.

Second: **premium-tier features** (Veo 3.1, Sora 2 Pro routes, 4K export). The product is whole without them.

Third: **iOS** (M8). It is genuinely deferrable; v1 is a Mac app.

Fourth: **secondary export targets** (YouTube/Vimeo direct publish). Users can export the MP4 and upload manually in v1; we add direct publish in M8 or later.

Last to cut: **the creative loop end-to-end** (M0–M5). If we can't ship a complete script-to-export loop, we don't have a product. Everything else is negotiable.
