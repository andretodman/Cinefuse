# AGENTS.md — Operating rules for AI coding agents on Cinefuse

This file is read by both **Cursor** and **Claude Code** at the start of any session. Cursor is configured via `.cursor/rules/cinefuse.mdc` to import this file; Claude Code reads it as `CLAUDE.md` (symlinked or copied at repo init). Treat it as binding. If you disagree with a rule here, raise the disagreement — do not silently ignore it.

This file deliberately avoids duplicating `PLAN.md`. Read `PLAN.md` first; this file tells you *how to work*, not *what to build*.

## Read order at session start

1. `PLAN.md` — the unified product and technical plan. If you have not read this in the current session, read it before proposing changes.
2. `MCP-ARCHITECTURE.md` — for any change that touches an MCP server, read the relevant section.
3. `MILESTONES.md` — to know which milestone the current work belongs to and what its acceptance criteria are.
4. The README of the package or app you're touching — every package has one.
5. Recently changed files (last 50 commits on `main`) for context on the active threads.

If you can't tell which milestone the current work belongs to, ask. Don't guess.

## Operating principles

**MCPs are the primary interface.** When adding new generation-related capabilities, the question is always "which MCP does this belong to" or "is this a new MCP." It is almost never "let me write a new internal HTTP endpoint." Internal HTTP exists only for the API gateway's user-facing surface (auth, project CRUD, file uploads) and webhooks. Any AI/generation capability is an MCP tool.

**Pubfuse is touched through one place only.** The `mcp/pubfuse/` server is the sole point of Pubfuse REST contact. If you find yourself writing `fetch('https://api.pubfuse.com/...')` anywhere else in the codebase, stop and route through the MCP. This rule exists because Pubfuse will evolve and we want the blast radius of any breaking change to be one file.

**Sparks debits go through `billing.debit` only.** Never write to the Spark ledger or the user's balance directly. Never assume the balance from a stale read; always quote-then-debit using the same idempotency key. The `billing` MCP is the only writer of the `spark_transactions` table.

**Cost-to-us is captured every time.** Every render job records `cost_to_us_cents` for the upstream provider call. If you're adding a new model integration, you must wire up the cost capture from day one. We cannot do unit economics if we forget for a quarter and try to backfill.

**Idempotency is non-optional for any state-changing operation.** Job creation, Spark debits, IAP redemptions, file uploads — every one of these has an idempotency key derived from a deterministic input hash. Retries don't double-spend.

**Privacy by default.** User-uploaded reference images, generated clips, audio tracks, and project archives all live in Pubfuse Files. Never log image content, prompt text, or generated output beyond the file ID. Logs that include prompts are scrubbed at the API gateway before they leave the gateway process.

**Tests track features, not the other way around.** If you add a tool to an MCP, you add a contract test for that tool in the same PR. CI will block. Don't disable the check; write the test.

## Repo layout (mirror of `PLAN.md` §7)

You are expected to know this from `PLAN.md`. The compressed reminder:

- `apps/mac/` — SwiftUI macOS editor. Owns the local MCP host.
- `apps/web/` — Next.js public site, creator dashboard, web playback.
- `apps/ios/` — Phase 4 iOS app, dormant in Phase 1.
- `mcp/<server>/` — one directory per MCP server. Each is a standalone Node.js or Python package.
- `services/` — `api-gateway` (Node), `render-worker` (Python), `webhook-receiver` (Node).
- `packages/` — shared TypeScript libs.
- `infra/` — Terraform, Docker, GitHub Actions.
- `tools/eval/` — quality eval harness; mandatory for any MCP that affects output quality.

## Per-language conventions

**Swift (Mac/iOS).** SwiftUI with the modern observation system (`@Observable`, not `@StateObject`). One feature per `Feature*` directory inside `apps/mac/Sources/`. Use `swift-format` with the project config; CI enforces. AVFoundation for video; do not pull in third-party video libraries unless `PLAN.md` is updated to allow it.

**TypeScript (web, MCP, services).** TypeScript strict mode, `noUncheckedIndexedAccess` on. ESLint config at the monorepo root; package-local overrides only when justified. Prefer `zod` for runtime validation at MCP and HTTP boundaries — every public input is validated. Prefer `pnpm` workspaces for package management. Node 22 LTS minimum.

**Python (render-worker, eval).** Python 3.12. `uv` for dep management, `ruff` for lint, `pyright` for types, `pytest` for tests. Long-running workers use `BullMQ-Python` or `RQ` to consume the same Redis queues the Node side produces to.

**Rust.** Not used in v1. If you find yourself wanting to add Rust, surface that decision to humans first; it has a maintenance cost we don't want to take on yet.

## Commit and PR conventions

Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `perf:`, `test:`. Scope optional but encouraged: `feat(clip): route Veo for premium dialogue shots`.

PRs include: a short summary of intent, the milestone (e.g. M3) the change belongs to, screenshots or a generated MP4 clip if the change is user-visible, and a checklist confirming `cost_to_us_cents` capture is in place if this PR touches a new model integration. PR descriptions are not optional — a one-line description is a sign the change isn't ready.

PRs that change pricing constants, Spark conversion rates, or model routing are reviewed by a human, never auto-merged, and never opened by an agent without explicit human direction.

## Things to ask before doing

The agent should pause and ask the user before:

1. **Adding a new external dependency** that costs money at scale (a new fal.ai-equivalent provider, a new Anthropic-tier API). The `PLAN.md` model registry config is the right place to extend, but the *decision to add* belongs to humans.
2. **Changing Spark prices** in the routing config. Even a 10% shift affects every active user.
3. **Modifying the content policy** (`packages/safety/policy.ts` or its successors). Policy changes require human sign-off and a written rationale committed to `PLAN.md` §10.
4. **Touching the `billing` MCP's ledger logic.** Read-only tool changes are fine; any change to debit/credit behavior is a high-risk PR.
5. **Modifying the IAP receipt validation flow.** Apple's contract is unforgiving and getting it wrong leaks revenue or causes refunds.
6. **Changing the C2PA watermarking pipeline.** This is a legal-compliance surface in some jurisdictions.

The agent does not need to ask before:

- Refactoring within a single MCP for clarity.
- Adding tests.
- Improving error messages.
- Updating dependencies that don't change behavior, where the lockfile diff is small.
- Documentation improvements to the README of any package.

## When working with `clip`, `audio`, and `character` MCPs

These three MCPs touch real money on every call. Special rules:

- **Always quote before generate.** The `quote_*` tool returns a Sparks cost; the API gateway shows the user the cost before they confirm. Never call `generate_*` from a path that hasn't been through a quote first.
- **Never silently retry across providers without telling the user.** If Wan fails and you fail over to LTX-2, the user is informed and the cost reflects whichever model actually produced the output.
- **Eval harness is non-optional.** Any change to the routing config, model adapter, or generation pipeline requires running `pnpm eval:clip` (or the Python equivalent for character) locally and pasting the diff in the PR.

## When working with `pubfuse` MCP

- The MCP is a *thin* wrapper. It does not add business logic on top of Pubfuse REST; it translates between MCP tool calls and HTTP. If you find yourself writing logic that's not "translate request, call Pubfuse, translate response," that logic belongs upstream in another MCP or in the API gateway.
- HMAC verification is non-negotiable on every webhook handler. If the verification fails, the request is dropped silently with a 401 and a structured log line.
- Cinefuse-specific endpoints that don't yet exist in Pubfuse (`/api/projects`, `/api/jobs`, etc.) initially live in the Cinefuse API gateway, not in the `pubfuse` MCP. The migration into Pubfuse proper happens after M6, per `PLAN.md` §4.

## Failure modes to expect and handle

These are real, observed failure modes. The agent should write code that handles them:

- **fal.ai rate limit.** Retry with exponential backoff up to 3 attempts; on the 4th, fail the job and refund Sparks via `billing.credit`.
- **Veo refusing a prompt for content reasons.** Surface the refusal text to the user verbatim so they can rephrase. Do not retry with prompt mutations behind their back.
- **Pubfuse 401 mid-session.** Token expired; trigger the SDK refresh flow on the Mac side and retry the request once.
- **ffmpeg OOM on long stitches.** Stitch operations chunk by 30-second windows when total runtime exceeds 2 minutes. The `stitch` MCP handles this internally; callers should not see it.
- **ElevenLabs returning malformed audio (rare).** Validate the WAV header before accepting; if invalid, regenerate once. After two failures, fall back to a simpler provider and inform the user.
- **Generated MP4 with audio out of sync.** Whisper-based alignment check at export time; if drift exceeds 200ms anywhere, re-mux with corrected offsets.

## How to ask the user good questions

When you genuinely need clarification, the question should be:

- **Specific.** Not "what should the UI look like" but "should the storyboard tab show a 4-column grid or a vertical timeline."
- **Bounded by 2–4 options.** Open-ended questions cost user time. Even when the design space is open, propose options.
- **Preceded by your best guess.** "I'm going to do X unless you say otherwise — flagging because Y. Should I proceed?"

The `ask_user_input_v0` tool (when running in Claude products) is preferable to a typed question for option-pick scenarios.

## Things this codebase will never do

Documenting these here so they don't have to be re-litigated:

1. **No on-device model inference in the Mac app.** All AI work happens server-side. Reasons: model weights are huge and licenses are nuanced; user expectation is fast, predictable performance regardless of their Mac generation; we want consistent quality across users.
2. **No third-party analytics tracking inside the editor.** Pubfuse's analytics surface is the only place user behavior is logged. We do not ship Mixpanel/Amplitude/Segment in the Mac binary.
3. **No A/B testing of generation quality without user consent.** Variant routing for cost optimization is fine; intentionally giving users different output quality without their knowledge is not.
4. **No silent data retention beyond what the privacy policy commits to.** When the user deletes a project, the cloud removes the rows and queues a 30-day-delayed file purge from Pubfuse Files. After the delay, files are gone. There is no "soft archive" we secretly keep.
5. **No self-hosted training of likeness models on user data.** The Stand-In LoRA is run per-project, not aggregated across users. We never train a foundation-class model on user content.

## Style and tone for user-facing copy

When the agent generates user-visible strings (error messages, tooltips, marketing copy in the app), follow the Cinefuse voice: confident, direct, builder-to-builder. Sentences end. Punctuation is honest. The product is a serious tool for creative people, not a toy. Avoid emoji except in deliberate marketing moments. Avoid "magic," "AI-powered," or "revolutionary"; users are tired of these words.

Examples of good copy:

- "This shot will cost 70 Sparks. Generate?"
- "Veo refused this prompt. Try rephrasing the action without the named celebrity."
- "Your render is done. 4:32 of finished video, exported to your Pubfuse files."

Examples of bad copy:

- "✨ AI Magic in Progress! ✨"
- "Whoops! Something went wrong 😅"
- "Get ready to revolutionize your filmmaking!"

When in doubt, write the sentence you'd want to read at 2am after a render failed.
