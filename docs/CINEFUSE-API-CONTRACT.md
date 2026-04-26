# Cinefuse HTTP API Contract (M0+)

This is the canonical REST contract for Cinefuse project pipeline APIs.
All clients and services should target these routes.

## Base prefix

`/api/v1/cinefuse`

## Resources

- `projects`
- `shots`
- `jobs`
- `sparks`

## Endpoints

### Projects

- `POST /api/v1/cinefuse/projects`
- `GET /api/v1/cinefuse/projects`
- `GET /api/v1/cinefuse/projects/{projectId}`

### Shots

- `POST /api/v1/cinefuse/projects/{projectId}/shots`
- `GET /api/v1/cinefuse/projects/{projectId}/shots`

### Jobs

- `POST /api/v1/cinefuse/projects/{projectId}/jobs`
- `GET /api/v1/cinefuse/projects/{projectId}/jobs`

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
