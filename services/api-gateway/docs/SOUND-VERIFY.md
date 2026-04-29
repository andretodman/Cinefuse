# Sound (ElevenLabs) verification

Same HTTP surface as the Mac app ([`APIClient.swift`](../../../packages/cinefuse-apple-core/Sources/CinefuseAppleCore/APIClient.swift)): `POST /api/v1/cinefuse/projects/{id}/shots/{shotId}/generate` with `{"generationKind":"sound","soundBlueprintIds":[]}`.

ElevenLabs runs **inside the API gateway** (audio MCP) when a render task executes—not in the client. The client only needs a valid Cinefuse `Bearer` token.

## Tier A — CI (no keys)

```bash
pnpm --filter @cinefuse/api-gateway test
pnpm --filter @cinefuse/mcp-audio contract-test
```

## Tier B — Live ElevenLabs on a dev gateway (costs API credits)

Requires `ELEVENLABS_API_KEY` in the **shell that runs the test** (the in-process gateway reads it). The test sets `CINEFUSE_GATEWAY_PUBLIC_ORIGIN` to the ephemeral server URL so internal ingest works.

```bash
export CINEFUSE_LIVE_ELEVENLABS_TEST=1
export ELEVENLABS_API_KEY='…'
unset CINEFUSE_ALLOW_STUB_MEDIA
pnpm --filter @cinefuse/api-gateway contract-test
```

The gated test name: `api contract: live ElevenLabs sound generation (gated; costs API credits)`.

## Tier C — Production / staging smoke (your bearer token)

Script (no secrets committed):

```bash
export CINEFUSE_VERIFY_BASE_URL='https://cinefuse.pubfuse.com'
export CINEFUSE_VERIFY_BEARER='Bearer …'   # or raw JWT; script adds Bearer if missing
export CINEFUSE_VERIFY_PROJECT_ID='…'
# Optional: existing shot UUID; if unset, script creates a new shot then generates
export CINEFUSE_VERIFY_SHOT_ID='…'

pnpm --filter @cinefuse/api-gateway verify:sound-smoke
```

Exit `0` when the shot reaches `ready` or `failed` (with job terminal state). Prints final shot + matching job JSON to stdout.

## Server log triage (gateway + worker)

Order of **gateway** `[render]` events for a healthy sound job:

1. `task_enqueued` (`backend: "redis"` or `"in-process"`)
2. `worker_process_invoked` (only when Redis + worker)
3. `task_started` … `audio_invoke_start` (`soundUploadMode` shows ingest branch)
4. `audio_invoke_done` (`hasSourceUrl: true`) then `task_completed`

**Audio MCP** JSON logs (stdout from gateway process):

- `elevenlabs_music_compose_ok` — ElevenLabs returned audio bytes
- `elevenlabs_music_upload_ok` — file persisted and URL resolved
- `audio_feature_skipped` with `reason` / `detail` — failure or skip before success

**Worker** (`render-worker`): `dequeued` → HTTP `POST …/internal/render/process` → `gateway render ok`

**Redis**: `redis_client_error` indicates connection drops; jobs may still complete if already processed.

## Client still “queued” while logs show `task_completed`

Re-fetch timeline + jobs against the **same** `CINEFUSE_VERIFY_BASE_URL` the app uses. The Mac app runs a second status pass after generate; if your build predates that, upgrade or pull latest `RootView` refresh behavior.
