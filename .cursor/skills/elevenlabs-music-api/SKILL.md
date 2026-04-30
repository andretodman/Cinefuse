# ElevenLabs Music API (Cinefuse)

Use when debugging **sound/score generation**, **`elevenlabs_music_*` errors**, **403 on `/v1/music`**, or aligning **`mcp/audio`** behavior with ElevenLabs docs.

## Credentials (never commit)

- Set **`ELEVENLABS_API_KEY`** in shell env, gateway `.env`, or MCP process env only.
- Never paste keys into Git, skills, PRs, or logs.

## Verified contract (compose)

Production-style success looks like:

- **POST** `https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128`
- **Headers:** `xi-api-key: <key>`, `Accept: audio/*,*/*`, `Content-Type: application/json`
- **JSON body:**

```json
{
  "prompt": "short instrumental cinematic underscore",
  "music_length_ms": 5000,
  "model_id": "music_v1",
  "force_instrumental": true
}
```

- **Success:** HTTP **200**, **`Content-Type: audio/mpeg`** (or similar audio), body is binary MP3 — **not** JSON.
- Response may include **`song-id`** (custom header).

### Smoke check (local)

```bash
export ELEVENLABS_API_KEY='your-key-here'
curl -sS -D - -o /tmp/el_music.mp3 \
  -X POST "https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128" \
  -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
  -H "Accept: audio/*,*/*" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"instrumental test","music_length_ms":5000,"model_id":"music_v1","force_instrumental":true}'
file /tmp/el_music.mp3   # expect MPEG Audio / MP3
```

If curl returns JSON with an error field, fix permissions/plan before debugging Cinefuse.

## Cinefuse implementation map

| Piece | Role |
|-------|------|
| `mcp/audio/src/server.js` → `elevenLabsComposeMusic` | Calls **`POST /v1/music`** with `output_format` query param, retries alternate **`ELEVENLABS_MUSIC_OUTPUT_FORMAT`** / MP3 presets on tier/format errors. |
| `resolveElevenLabsApiBase()` | Uses **`ELEVENLABS_API_BASE_URL`** or default `https://api.elevenlabs.io`. EU/US residency hosts supported if your account requires them. |
| `validateElevenLabsMusicBinaryBody` | Rejects JSON/error payloads mistaken for audio — surfaces **`elevenlabs_music_response_was_json_not_audio`**. |

See repo `.env.example` § ElevenLabs for **`ELEVENLABS_*`** and **`CINEFUSE_AUDIO_*`** (upload URL, stub flags).

## Common failures

| Symptom | Likely cause |
|---------|----------------|
| **403** on `/v1/music` | Restricted API key missing **`music_generation`**. In ElevenLabs dashboard: edit key → enable Music / music generation, or use an unrestricted key. |
| **402** / quota / tier messages | Paid Music capability or credits; may need Creator/Pro plan per ElevenLabs. |
| **400 / 422** mentioning `output_format`, PCM, bitrate | Wrong **`ELEVENLABS_MUSIC_OUTPUT_FORMAT`** for plan — unset override or use **`mp3_44100_128`** (see fallback chain in `server.js`). |
| **`elevenlabs_music_response_was_json_not_audio`** | API returned JSON (often error); log shows snippet — fix key/permissions/plan, not binary parsing. |
| Stub sine tone instead of real music | **`CINEFUSE_ALLOW_STUB_MEDIA`** enabled — disable for real ElevenLabs. |

## Gateway / MCP wiring checklist

1. **`ELEVENLABS_API_KEY`** set on the **audio MCP** process (same env as `node mcp/audio`).
2. **`CINEFUSE_AUDIO_UPLOAD_URL`** (or gateway internal upload + **`CINEFUSE_GATEWAY_PUBLIC_ORIGIN`**) so generated MP3 lands in Pubfuse Files — see `.env.example`.
3. Run **`pnpm --filter @cinefuse/mcp-audio test`** after changing validators or compose logic.

## Cinefuse Apple editor (preview / timeline)

When debugging **audio preview** or **timeline playback chrome** in the Swift editor (`packages/cinefuse-apple-core`):

- **Audio preview** decodes peaks from the **same local `file://` URL** the preview player uses (`WaveformPeakLoader` → linear PCM via `AVAssetReader`), draws **`AudioWaveformWithPlayhead`**, and shares transport state through **`EditorPlaybackState`** (`PlaybackTimelineScrubber`, scrub/seek).
- **Video preview** uses the same **`PlaybackTimelineScrubber`** under the QuickTime-style surface so **current time / duration** track the file.
- **Horizontal timeline cards** get widths **proportional to `Shot.durationSec`** (scaled to the viewport; scroll when the natural strip is wider). Active-clip playhead on a card uses **`activeShotId`** + player time when preview matches that shot.

This is client-side only; ElevenLabs compose/upload behavior is unchanged.

## References

- ElevenLabs: [Compose music API](https://elevenlabs.io/docs/api-reference/music/compose)
- Internal: `mcp/audio/src/server.js` (`elevenLabsComposeMusic`, `validateElevenLabsMusicBinaryBody`)
