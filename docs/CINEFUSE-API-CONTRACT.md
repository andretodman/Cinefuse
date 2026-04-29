# Cinefuse HTTP API Contract (M0+)

This is the canonical REST contract for Cinefuse project pipeline APIs.
All clients and services should target these routes.

## Base prefix

`/api/v1/cinefuse`

## Resources

- `projects`
- `shots`
- `jobs`
- `sound-blueprints` (audio creation)
- `sparks`

## Endpoints

### Projects

- `POST /api/v1/cinefuse/projects`
- `GET /api/v1/cinefuse/projects`
- `GET /api/v1/cinefuse/projects/{projectId}`

### Shots

- `POST /api/v1/cinefuse/projects/{projectId}/shots`
- `GET /api/v1/cinefuse/projects/{projectId}/shots`
- `POST /api/v1/cinefuse/projects/{projectId}/shots/quote`
- `POST /api/v1/cinefuse/projects/{projectId}/shots/{shotId}/generate`

### Jobs

- `POST /api/v1/cinefuse/projects/{projectId}/jobs`
- `GET /api/v1/cinefuse/projects/{projectId}/jobs`

### Sound blueprints (audio creation)

- `GET /api/v1/cinefuse/projects/{projectId}/sound-blueprints` → `{ "soundBlueprints": [...] }`
- `POST /api/v1/cinefuse/projects/{projectId}/sound-blueprints` → `{ "soundBlueprint": { ... } }`  
  Body: `{ "name": string, "templateId"?: string, "referenceFileIds"?: string[] }`

### Audio generation (MCP-backed)

Each route invokes the `audio` MCP with a deterministic idempotency key. Responses are **`200`** with either a persisted track or a **non-blocking skip** (workflow continues).

- `POST /api/v1/cinefuse/projects/{projectId}/audio/dialogue`
- `POST /api/v1/cinefuse/projects/{projectId}/audio/score`
- `POST /api/v1/cinefuse/projects/{projectId}/audio/sfx`
- `POST /api/v1/cinefuse/projects/{projectId}/audio/mix`
- `POST /api/v1/cinefuse/projects/{projectId}/audio/lipsync`

**Success with artifact**

```json
{
  "audioTrack": { "...": "..." },
  "job": { "kind": "audio", "status": "done", "outputUrl": "...", "skippedFeature": false, "...": "..." },
  "sparksCost": 15,
  "skipped": false
}
```

**Skipped feature (provider cannot fulfill; no Spark debit)**

```json
{
  "audioTrack": null,
  "job": {
    "kind": "audio",
    "status": "done",
    "skippedFeature": true,
    "featureError": { "provider": "...", "reason": "...", "detail": "..." },
    "providerAdapter": "...",
    "outputCreated": false
  },
  "sparksCost": 0,
  "skipped": true
}
```

Clients should refresh jobs/timeline and surface `skippedFeature` / `featureError` in diagnostics (same pattern as clip/export jobs).

### Audio export (layered mixdown)

- `POST /api/v1/cinefuse/projects/{projectId}/export/audio-mix` → `{ "job": {...}, "export": { "fileUrl", "sparksCost", "costToUsCents" } }`  
  Mixes current `audio-tracks` via export MCP `encode_audio_mixdown` and records a job with `kind: "audio_export"`. Optional JSON body `{ "idempotencyKey": "<string>" }`; default key is `export-audio-mix:{projectId}` for billing/MCP correlation.

### Sparks

- `GET /api/v1/cinefuse/sparks/balance`
- `POST /api/v1/cinefuse/sparks/debit`
- `POST /api/v1/cinefuse/sparks/credit`

## Error envelope

All non-2xx responses use:

```json
{
  "error": "<message>",
  "code": "<MACHINE_CODE>"
}
```

Examples:

- `401`: `{"error":"unauthorized","code":"UNAUTHORIZED"}`
- `404`: `{"error":"project not found","code":"PROJECT_NOT_FOUND"}`

## Compatibility alias (temporary)

During migration, legacy Cinefuse gateway route `/v1/projects` may remain as an alias to:

- `GET /api/v1/cinefuse/projects`
- `POST /api/v1/cinefuse/projects`

Legacy Spark balance route `/v1/sparks/balance` may remain as an alias to:

- `GET /api/v1/cinefuse/sparks/balance`

Alias removal is allowed after iOS/Android/Cinefuse clients adopt the canonical prefix.
