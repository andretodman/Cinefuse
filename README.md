# Cinefuse

> **Working title:** Cinefuse (replaces "MovieKit" — see naming note below)
> **Tagline:** *Make movies with your imagination. Powered by Pubfuse.*
> **Status:** Plan v1.0 — ready for build kickoff.

Cinefuse is a desktop-and-cloud movie creation platform built on the **Pubfuse SDK**. Users describe a story, Cinefuse generates clips with consistent characters, composes the score and dialogue, stitches scenes together, and exports a finished film. Generation is paid for in **Pubfuse Sparks** — purchased in-app via Apple's StoreKit (App Store) or directly from Pubfuse.

This repository is a **planning bundle**. It is the unified source of truth for the build. Both Cursor and Claude Code should read these files in order before proposing or writing any code.

---

## Why a new name?

The user's working title was "MovieKit." Apple ships a framework called **MovieKit** as part of their media frameworks on visionOS/macOS. Shipping a Mac app named MovieKit is a guaranteed App Store rejection and a trademark conflict. The recommended name is **Cinefuse** — it carries the Pubfuse brand suffix, signals cinema, and is a clean .com / App Store search candidate.

Alternative names ranked: Cinefuse > Reelfuse > Sparkreel > Cinepub > Fuseframe. Final pick is up to product/marketing — but it must not be MovieKit.

---

## How to read this bundle

| File | What it covers | Audience |
|---|---|---|
| `README.md` (this file) | Executive overview, decisions at a glance | Everyone |
| `PLAN.md` | The full unified product, technical, and monetization plan | Engineers + AI agents |
| `AGENTS.md` | Operating rules for Cursor and Claude Code agents working on the codebase | AI coding agents |
| `MILESTONES.md` | Phased delivery roadmap with acceptance criteria per phase | PM + engineering leads |
| `MONETIZATION.md` | Spark economy, pricing tiers, IAP plan, unit economics | Founders + finance |
| `MCP-ARCHITECTURE.md` | MCP server specs — one file per server, with tool surfaces | Engineers + AI agents |

Read in this order: `README.md` → `PLAN.md` → `AGENTS.md` → the rest as needed.

---

## The decisions, at a glance

**Platform.** Native **macOS (SwiftUI)** for the desktop editor. **Next.js (React)** web app for the cloud platform, the share/playback hub, and the marketing site. **Node.js + Python** services on the cloud render backend. Eventually iOS and iPadOS share the SwiftUI codebase. Windows is deliberately deferred — see PLAN.md §3 for the rationale.

**Why not Electron/Tauri.** A cross-platform JS-based desktop would save effort on day one but cost the App Store IAP path for Sparks (StoreKit requires a native binary), slow the video editor's responsiveness, and force us to reinvent what AVFoundation gives us free. Pubfuse already has iOS patterns we can port to macOS. The platform choice is locked to native.

**Architecture.** MCP-first. Eight MCP servers — `pubfuse`, `clip`, `character`, `audio`, `script`, `stitch`, `export`, `billing` — each owning one bounded domain. The Mac app, the cloud render workers, Cursor, and Claude Code all consume the same MCPs. New features become new MCPs or new tools on existing MCPs; nothing else has to change. Full specs in `MCP-ARCHITECTURE.md`.

**Pubfuse integration.** Cinefuse registers as a **new SDK Client** with its own API key and HMAC secret. We do not extend Pubfuse on day one. Once the Cinefuse-specific endpoints stabilize (movie projects, scene timelines, clip jobs, render queue), we lift them into Pubfuse so future apps inherit them. PLAN.md §4 details which endpoints stay in Cinefuse vs. eventually migrate.

**Video models.** Tiered. Budget tier uses Wan 2.6 / LTX-2 (~$0.04–$0.08/sec via fal.ai). Standard tier uses Kling 2.5 Turbo Pro (~$0.07/sec) and Hailuo 2.3 Pro (~$0.49 per 6s clip). Premium tier uses Veo 3.1 ($0.20–$0.40/sec with native audio) and Sora 2 Pro ($0.30–$0.50/sec). Phase 3 adds self-hosted Wan 2.2 on H100s for margin compression. Character consistency uses **Stand-In LoRA + Wan 2.x** as the core approach.

**Sparks economy.** 1 Spark ≈ $0.01 of effective spend. A 5-second budget clip costs the user ~50 Sparks (we pay ~$0.25 to fal.ai, charge $0.50). The Spark balance lives in the Pubfuse user model already (`balance` field). Initial seeding is a hard-coded large number per the spec ("All users have a lot of sparks to begin with"); the IAP top-up subsystem is built behind a feature flag and turned on in Phase 2. Full pricing in `MONETIZATION.md`.

**Realistic revenue model.** A casual user generating one 30-second short per week at standard tier spends ~1,200 Sparks/month ≈ $12 in Spark equivalent. Power users producing a full 5-minute short per month spend 30,000–60,000 Sparks ≈ $300–$600. We project ~30–40% gross margin in Phase 1 (all hosted models), rising to 55–65% in Phase 3 (self-hosted budget tier). See `MONETIZATION.md` for unit economics, target ARPU, and breakeven assumptions.

---

## Milestones, one-liner each

1. **M0 — Foundations (week 1–3).** Repos, CI, Pubfuse SDK Client provisioned, MCP scaffolds for `pubfuse` and `billing`, "hello world" Mac app authenticates against Pubfuse and reads its Spark balance.
2. **M1 — Clip generation (week 4–7).** `clip` MCP wired to fal.ai (Wan 2.6 + Kling). User can generate a single clip from a prompt and see it in the timeline. Sparks debited per clip.
3. **M2 — Script & storyboard (week 8–10).** `script` MCP using Claude API generates a multi-scene plot, beat sheet, and per-shot prompts. Storyboard view in the editor.
4. **M3 — Character consistency (week 11–14).** `character` MCP — upload a reference photo, train/store identity embedding, lock characters across scenes via Stand-In LoRA on Wan 2.x.
5. **M4 — Audio (week 15–17).** `audio` MCP — TTS dialogue (ElevenLabs), score (Suno or MusicGen), SFX library, mix-down per scene.
6. **M5 — Stitch & export (week 18–20).** `stitch` MCP — ffmpeg-based timeline assembly, cross-fades, color match, captions. `export` MCP — final encode in 1080p/4K, push to Pubfuse Files, optional publish to the Pubfuse stream platform.
7. **M6 — IAP & live billing (week 21–23).** StoreKit IAP for Sparks, server-side receipt validation, ledger reconciliation, Pubfuse webhook for spend events.
8. **M7 — Public beta (week 24–26).** Onboarding, sample projects, share-to-Pubfuse community feature, pricing pages, support flow, App Store submission.
9. **M8 — GA & growth (week 27+).** Phase 3 self-hosted budget tier, iOS companion, web preview-only viewer, referral program.

Detailed acceptance criteria for each milestone are in `MILESTONES.md`.

---

## What this plan deliberately does **not** do

- **No Windows desktop in v1.** The product is Mac-first because the Mac App Store is where Sparks IAP lives and because the target user (creators with M-series machines) is Mac-heavy. Windows is a Phase 4 question, not a Phase 1 one.
- **No real-time editor collaboration.** Pubfuse has LiveKit, but multi-user co-editing of a film project is a 6–12 month feature in its own right. v1 is single-author; the cloud is for rendering and sharing only.
- **No copyrighted character/voice cloning.** The character system locks identity from a user-supplied reference photo of *their* character or *themselves*. The product refuses to clone celebrities or copyrighted characters at the policy layer.
- **No "fully automatic blockbuster" promise.** The marketing must be honest. Cinefuse drastically lowers the floor for making a coherent, watchable short film. It does not output Christopher Nolan's next picture from a one-line prompt. Internal language: *"From idea to watchable film in an afternoon."*

---

## Open questions for the founder before kickoff

1. **Pubfuse data residency.** Are Cinefuse renders stored in the same Pubfuse object storage as live-stream artifacts, or in a separate bucket with its own lifecycle policy? PLAN.md §4 assumes same bucket with a `cinefuse/` prefix; confirm.
2. **Pubfuse user model field for Spark balance.** The spec says "amounts hard coded into the database field." Confirm the field name (`sparks_balance` recommended) and whether it lives on the Pubfuse `users` table or a new `cinefuse_wallets` table.
3. **App Store entity.** Does the Cinefuse app ship under the existing Pubfuse Inc. App Store team, or a new DBA? This affects IAP product configuration and review timeline.
4. **AI ethics policy.** Final wording on what the product refuses to generate — public figures, minors, weapons-in-violence, etc. Draft policy in PLAN.md §10.
5. **Beta exclusivity.** Closed beta via TestFlight, or public beta from day one? Closed is safer; public is louder.

These do not block planning. They block code in M0.
