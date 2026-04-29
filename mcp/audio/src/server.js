import { randomUUID } from "node:crypto";

const TOOLS = [
  "quote_sound",
  "generate_dialogue",
  "generate_score",
  "lookup_sfx",
  "generate_sfx",
  "mix_scene",
  "lipsync"
];

/**
 * Sounds / score tier: sparks aligned with clip tiers for UX parity.
 * `modelId` is ElevenLabs Music (`music_v1`) — see https://elevenlabs.io/docs/api-reference/music/compose
 */
const SOUND_TIER_CONFIG = {
  budget: { sparks: 50, modelId: "music_v1", estimatedDurationSec: 5, costToUsCents: 28 },
  standard: { sparks: 70, modelId: "music_v1", estimatedDurationSec: 5, costToUsCents: 40 },
  premium: { sparks: 250, modelId: "music_v1", estimatedDurationSec: 5, costToUsCents: 120 }
};

function resolveSoundTierConfig(modelTier) {
  return SOUND_TIER_CONFIG[modelTier] ?? SOUND_TIER_CONFIG.budget;
}

function isTestMode() {
  return process.env.CINEFUSE_ALLOW_STUB_MEDIA === "true"
    || process.argv.includes("--test");
}

function structuredLog(level, event, fields) {
  const line = JSON.stringify({
    level,
    event,
    server: "audio",
    ts: new Date().toISOString(),
    ...fields
  });
  if (level === "error") {
    console.error(line);
  } else {
    console.log(line);
  }
}

function stubMediaRootUrl() {
  const explicit = process.env.CINEFUSE_PUBLIC_FILES_BASE_URL?.replace(/\/$/, "");
  if (explicit) {
    return explicit;
  }
  const gw = process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN?.replace(/\/$/, "");
  if (gw) {
    return `${gw}/api/v1/cinefuse/stub-media`;
  }
  return "https://files.cinefuse.test";
}

function fallbackTrack(kind, input = {}) {
  const id = randomUUID();
  const root = stubMediaRootUrl();
  return {
    id,
    kind,
    status: "ready",
    sourceUrl: `${root}/audio/${kind}/${id}.wav`,
    waveformUrl: `${root}/audio/${kind}/${id}.png`,
    durationMs: Number(input.durationMs ?? 4000),
    laneIndex: Number(input.laneIndex ?? 0),
    startMs: Number(input.startMs ?? 0),
    costToUsCents: Number(input.costToUsCents ?? 9),
    sparksCost: Number(input.sparksCost ?? 15)
  };
}

function resolveAudioAdapterKind() {
  return (process.env.CINEFUSE_AUDIO_ADAPTER ?? "generic").toLowerCase();
}

function resolveProviderUrl(tool) {
  const explicitByTool = {
    generate_dialogue: process.env.CINEFUSE_AUDIO_DIALOGUE_PROVIDER_URL,
    generate_score: process.env.CINEFUSE_AUDIO_SCORE_PROVIDER_URL,
    generate_sfx: process.env.CINEFUSE_AUDIO_SFX_PROVIDER_URL,
    mix_scene: process.env.CINEFUSE_AUDIO_MIX_PROVIDER_URL,
    lipsync: process.env.CINEFUSE_AUDIO_LIPSYNC_PROVIDER_URL
  };
  return explicitByTool[tool] ?? process.env.CINEFUSE_AUDIO_PROVIDER_URL ?? "";
}

function providerHeaders(token) {
  return {
    "content-type": "application/json",
    ...(token ? { authorization: `Bearer ${token}` } : {})
  };
}

function normalizeTrack(rawTrack, kind, input = {}) {
  const id = typeof rawTrack?.id === "string" && rawTrack.id.length > 0 ? rawTrack.id : randomUUID();
  const sourceUrl = rawTrack?.sourceUrl ?? rawTrack?.url ?? null;
  if (typeof sourceUrl !== "string" || sourceUrl.length === 0) {
    throw new Error("audio provider returned no sourceUrl");
  }
  return {
    id,
    kind,
    status: rawTrack?.status ?? "ready",
    sourceUrl,
    waveformUrl: rawTrack?.waveformUrl ?? null,
    durationMs: Number(rawTrack?.durationMs ?? input.durationMs ?? 4000),
    laneIndex: Number(rawTrack?.laneIndex ?? input.laneIndex ?? 0),
    startMs: Number(rawTrack?.startMs ?? input.startMs ?? 0),
    costToUsCents: Number(rawTrack?.costToUsCents ?? input.costToUsCents ?? 9),
    sparksCost: Number(rawTrack?.sparksCost ?? input.sparksCost ?? 15)
  };
}

async function callAudioProvider(tool, kind, input = {}) {
  const url = resolveProviderUrl(tool);
  if (!url) {
    throw new Error("no_http_provider_url");
  }
  const token = process.env.CINEFUSE_AUDIO_PROVIDER_TOKEN ?? "";
  const response = await fetch(url, {
    method: "POST",
    headers: providerHeaders(token),
    body: JSON.stringify({
      tool,
      kind,
      input
    }),
    signal: AbortSignal.timeout(120_000)
  });
  if (!response.ok) {
    throw new Error(`audio provider error (${response.status}): ${await response.text()}`);
  }
  const payload = await response.json();
  return normalizeTrack(payload.track ?? payload.audioTrack ?? payload, kind, input);
}

function extractDialogueText(input = {}) {
  if (typeof input.text === "string" && input.text.trim().length > 0) {
    return input.text.trim();
  }
  if (typeof input.prompt === "string" && input.prompt.trim().length > 0) {
    return input.prompt.trim();
  }
  if (Array.isArray(input.lines)) {
    const joined = input.lines
      .map((line) => (typeof line === "string" ? line : line?.text ?? ""))
      .filter(Boolean)
      .join("\n");
    if (joined.trim().length > 0) {
      return joined.trim();
    }
  }
  return "";
}

/** Prompt for ElevenLabs Music compose (`generate_score`). */
function extractMusicPrompt(input = {}) {
  if (typeof input.prompt === "string" && input.prompt.trim().length > 0) {
    return input.prompt.trim();
  }
  if (typeof input.mood === "string" && input.mood.trim().length > 0) {
    return `Instrumental ${input.mood.trim()} mood music for picture`;
  }
  return "";
}

/** Default Music output: MP3 44.1kHz 128kbps — supported below Pro-only PCM presets (see ElevenLabs Music docs). */
const ELEVENLABS_MUSIC_FORMAT_FALLBACK_CHAIN = ["mp3_44100_128", "mp3_44100_96", "mp3_22050_32"];

function resolveElevenLabsApiBase() {
  const fallback = "https://api.elevenlabs.io";
  const raw = (process.env.ELEVENLABS_API_BASE_URL ?? "").trim();
  const base = raw.length > 0 ? raw : fallback;
  return base.replace(/\/+$/, "");
}

/**
 * ElevenLabs Music: instrumental (or prompt-led) generation via Compose API
 * (`POST /v1/music`, same capability as the ElevenCreative Music product in the web UI).
 * Restricted API keys must include permission `music_generation` or the request returns 403.
 * Retries with safer MP3 presets when the API rejects `output_format` (e.g. Pro-only PCM on Creator).
 */
async function elevenLabsComposeMusic({ prompt, musicLengthMs, forceInstrumental = true }) {
  const apiKey = process.env.ELEVENLABS_API_KEY ?? "";
  if (!apiKey) {
    throw new Error("elevenlabs_missing_api_key");
  }
  const length = Math.min(600_000, Math.max(3000, Number(musicLengthMs ?? 30_000)));
  const promptText =
    typeof prompt === "string" && prompt.trim().length > 0
      ? prompt.trim()
      : "instrumental cinematic underscore";
  const envFormat = (process.env.ELEVENLABS_MUSIC_OUTPUT_FORMAT ?? "").trim();
  const formatCandidates = [];
  if (envFormat.length > 0) {
    formatCandidates.push(envFormat);
  }
  for (const f of ELEVENLABS_MUSIC_FORMAT_FALLBACK_CHAIN) {
    if (!formatCandidates.includes(f)) {
      formatCandidates.push(f);
    }
  }
  const base = resolveElevenLabsApiBase();
  let lastStatus = 0;
  let lastBody = "";
  let lastFormat = "";
  for (const outputFormat of formatCandidates) {
    lastFormat = outputFormat;
    const url = new URL(`${base}/v1/music`);
    url.searchParams.set("output_format", outputFormat);
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "xi-api-key": apiKey,
        accept: "audio/*,*/*",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        prompt: promptText,
        music_length_ms: length,
        model_id: "music_v1",
        force_instrumental: forceInstrumental
      }),
      signal: AbortSignal.timeout(300_000)
    });
    if (response.ok) {
      const providerRequestId =
        response.headers.get("request-id") ??
        response.headers.get("x-request-id") ??
        response.headers.get("xi-request-id") ??
        null;
      const buffer = Buffer.from(await response.arrayBuffer());
      return { buffer, providerRequestId };
    }
    const errBody = await response.text();
    lastStatus = response.status;
    lastBody = errBody;
    const canRetryOtherFormat =
      outputFormat !== formatCandidates[formatCandidates.length - 1]
      && (response.status === 400 || response.status === 422)
      && /output_format|pcm|sample_rate|bitrate|format|encode|unsupported|invalid|quality|tier|plan|subscription/i.test(
        errBody
      );
    if (canRetryOtherFormat) {
      structuredLog("warn", "elevenlabs_music_retry_output_format", {
        failedFormat: outputFormat,
        status: response.status,
        detail: errBody.slice(0, 400)
      });
      continue;
    }
    break;
  }
  const permissionHint =
    lastStatus === 403
      ? " If this key is restricted in ElevenLabs → Developers → API keys, enable Music (permission: music_generation) or use a key with full access."
      : "";
  const planHint =
    lastStatus === 402
    || /pcm|44\.?1|output_format|format|tier|plan|subscription|quota|credit/i.test(lastBody)
      ? " Creator supports Music API with MP3 (e.g. mp3_44100_128). Pro adds PCM 44.1kHz via API; if you overrode ELEVENLABS_MUSIC_OUTPUT_FORMAT with PCM, remove it. EU residency: set ELEVENLABS_API_BASE_URL (see ElevenLabs docs for your region)."
      : "";
  throw new Error(
    `elevenlabs_music_http_${lastStatus} (format=${lastFormat}): ${lastBody.slice(0, 800)}${permissionHint}${planHint}`
  );
}

async function elevenLabsTextToSpeech(text) {
  const apiKey = process.env.ELEVENLABS_API_KEY ?? "";
  if (!apiKey) {
    throw new Error("elevenlabs_missing_api_key");
  }
  const voiceId = process.env.ELEVENLABS_VOICE_ID ?? "21m00Tcm4TlvDq8ikWAM";
  const modelId = process.env.ELEVENLABS_MODEL_ID ?? "eleven_turbo_v2";
  const url = `${resolveElevenLabsApiBase()}/v1/text-to-speech/${voiceId}`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "xi-api-key": apiKey,
      accept: "audio/mpeg",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      text,
      model_id: modelId
    }),
    signal: AbortSignal.timeout(120_000)
  });
  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`elevenlabs_http_${response.status}: ${errBody.slice(0, 500)}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

function resolveUploadedAssetUrl(payload, uploadPostUrl) {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  if (typeof payload.url === "string" && payload.url.length > 0) {
    return payload.url;
  }
  if (typeof payload.fileUrl === "string" && payload.fileUrl.length > 0) {
    return payload.fileUrl;
  }
  if (typeof payload.sourceUrl === "string" && payload.sourceUrl.length > 0) {
    return payload.sourceUrl;
  }
  const file = payload.file;
  if (file && typeof file === "object") {
    if (typeof file.url === "string" && file.url.length > 0) {
      return file.url;
    }
    if (typeof file.id === "string" && file.id.length > 0 && typeof uploadPostUrl === "string") {
      const base = uploadPostUrl.replace(/\/+$/, "");
      if (base.endsWith("/files")) {
        return `${base}/${encodeURIComponent(file.id)}`;
      }
    }
  }
  return null;
}

/**
 * POST raw audio bytes. `options.uploadUrl` overrides `CINEFUSE_AUDIO_UPLOAD_URL`.
 * Cinefuse gateway returns `{ file: { id, url? } }`; other bridges may return top-level `url`.
 */
async function uploadAudioBuffer(buffer, contentType = "audio/mpeg", options = {}) {
  const envUrl = (process.env.CINEFUSE_AUDIO_UPLOAD_URL ?? "").trim();
  let uploadUrl =
    (typeof options.uploadUrl === "string" && options.uploadUrl.length > 0 ? options.uploadUrl : envUrl).trim();
  const useWorkerIngest =
    typeof options.uploadWorkerToken === "string"
    && options.uploadWorkerToken.length > 0
    && typeof options.uploadProjectId === "string"
    && options.uploadProjectId.length > 0
    && typeof options.uploadUserId === "string"
    && options.uploadUserId.length > 0;
  if (!uploadUrl && useWorkerIngest) {
    const base = (
      process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN
      ?? process.env.CINEFUSE_API_BASE_URL
      ?? ""
    )
      .trim()
      .replace(/\/+$/, "");
    if (base.length > 0) {
      uploadUrl = `${base}/api/v1/internal/render/project-audio`;
    }
  }
  if (!uploadUrl) {
    return null;
  }
  let auth = "";
  if (!useWorkerIngest) {
    if (typeof options.authorizationHeader === "string" && options.authorizationHeader.trim().length > 0) {
      auth = options.authorizationHeader.trim();
    } else if ((process.env.CINEFUSE_AUDIO_UPLOAD_TOKEN ?? "").trim().length > 0) {
      auth = `Bearer ${process.env.CINEFUSE_AUDIO_UPLOAD_TOKEN.trim()}`;
    } else if ((process.env.CINEFUSE_AUDIO_PROVIDER_TOKEN ?? "").trim().length > 0) {
      auth = `Bearer ${process.env.CINEFUSE_AUDIO_PROVIDER_TOKEN.trim()}`;
    }
  }
  const filename =
    (typeof options.filename === "string" && options.filename.length > 0 ? options.filename : "score.mp3")
      .replace(/[^\w.\-]+/g, "_");
  const headers = {
    "content-type": contentType,
    "x-filename": filename,
    ...(auth ? { authorization: auth } : {}),
    ...(useWorkerIngest
      ? {
          "x-cinefuse-worker-token": options.uploadWorkerToken,
          "x-cinefuse-project-id": options.uploadProjectId,
          "x-cinefuse-user-id": options.uploadUserId
        }
      : {})
  };
  const response = await fetch(uploadUrl, {
    method: "POST",
    headers,
    body: buffer,
    signal: AbortSignal.timeout(120_000)
  });
  if (!response.ok) {
    throw new Error(`audio_upload_error (${response.status}): ${await response.text()}`);
  }
  const payload = await response.json().catch(() => ({}));
  const uploaded = resolveUploadedAssetUrl(payload, uploadUrl);
  if (typeof uploaded !== "string" || uploaded.length === 0) {
    throw new Error("audio_upload_missing_url_in_response");
  }
  return uploaded;
}

function skipResult({
  tool,
  input,
  provider,
  reason,
  detail,
  outputCreated = false
}) {
  const projectId = typeof input?.projectId === "string" ? input.projectId : "";
  const requestId = typeof input?.idempotencyKey === "string"
    ? input.idempotencyKey
    : (typeof input?.requestId === "string" ? input.requestId : "");
  structuredLog("warn", "audio_feature_skipped", {
    provider,
    tool,
    projectId,
    requestId,
    reason,
    detail: typeof detail === "string" ? detail.slice(0, 800) : detail
  });
  return {
    ok: true,
    skipped: true,
    skippedFeature: tool,
    outputCreated,
    providerAdapter: provider,
    featureError: {
      provider,
      reason,
      detail: typeof detail === "string" ? detail.slice(0, 2000) : String(detail ?? "")
    },
    track: null
  };
}

async function runGenerateDialogue(tool, kind, input) {
  const httpUrl = resolveProviderUrl(tool);
  if (httpUrl) {
    try {
      const track = await callAudioProvider(tool, kind, input);
      return {
        ok: true,
        skipped: false,
        outputCreated: true,
        providerAdapter: resolveAudioAdapterKind(),
        track: {
          ...track,
          providerAdapter: resolveAudioAdapterKind()
        }
      };
    } catch (err) {
      return skipResult({
        tool,
        input,
        provider: "http_adapter",
        reason: "provider_call_failed",
        detail: err instanceof Error ? err.message : String(err),
        outputCreated: false
      });
    }
  }

  if (isTestMode()) {
    const track = fallbackTrack(kind, input);
    return {
      ok: true,
      skipped: false,
      outputCreated: true,
      providerAdapter: "stub",
      track: { ...track, providerAdapter: "stub" }
    };
  }

  const text = extractDialogueText(input);
  if (!text) {
    return skipResult({
      tool,
      input,
      provider: "elevenlabs",
      reason: "missing_dialogue_text",
      detail: "Provide text, prompt, or lines[] for dialogue generation.",
      outputCreated: false
    });
  }

  if (!process.env.ELEVENLABS_API_KEY) {
    return skipResult({
      tool,
      input,
      provider: "none",
      reason: "no_dialogue_provider",
      detail: "Set CINEFUSE_AUDIO_DIALOGUE_PROVIDER_URL or ELEVENLABS_API_KEY (and optional CINEFUSE_AUDIO_UPLOAD_URL for direct ElevenLabs output).",
      outputCreated: false
    });
  }

  try {
    const audioBuffer = await elevenLabsTextToSpeech(text);
    const uploadedUrl = await uploadAudioBuffer(audioBuffer, "audio/mpeg", {
      uploadUrl: typeof input.uploadUrl === "string" ? input.uploadUrl : undefined,
      authorizationHeader: typeof input.uploadAuthorization === "string"
        ? input.uploadAuthorization
        : undefined,
      filename: typeof input.uploadFilename === "string" ? input.uploadFilename : "dialogue.mp3"
    });
    if (!uploadedUrl) {
      return skipResult({
        tool,
        input,
        provider: "elevenlabs",
        reason: "elevenlabs_audio_requires_upload_url",
        detail: "ElevenLabs returned audio but CINEFUSE_AUDIO_UPLOAD_URL is not set to persist a public URL.",
        outputCreated: false
      });
    }
    const track = normalizeTrack(
      {
        sourceUrl: uploadedUrl,
        durationMs: input.durationMs,
        laneIndex: input.laneIndex,
        startMs: input.startMs,
        costToUsCents: input.costToUsCents ?? 12,
        sparksCost: input.sparksCost ?? 15
      },
      kind,
      input
    );
    return {
      ok: true,
      skipped: false,
      outputCreated: true,
      providerAdapter: "elevenlabs",
      track: { ...track, providerAdapter: "elevenlabs" }
    };
  } catch (err) {
    return skipResult({
      tool,
      input,
      provider: "elevenlabs",
      reason: "elevenlabs_or_upload_failed",
      detail: err instanceof Error ? err.message : String(err),
      outputCreated: false
    });
  }
}

async function runGenerateScore(tool, kind, input) {
  const httpUrl = resolveProviderUrl(tool);
  if (httpUrl) {
    try {
      const track = await callAudioProvider(tool, kind, input);
      return {
        ok: true,
        skipped: false,
        outputCreated: true,
        providerAdapter: resolveAudioAdapterKind(),
        providerEndpoint: httpUrl,
        providerRequestId: null,
        track: {
          ...track,
          providerAdapter: resolveAudioAdapterKind()
        }
      };
    } catch (err) {
      return skipResult({
        tool,
        input,
        provider: "http_adapter",
        reason: "provider_call_failed",
        detail: err instanceof Error ? err.message : String(err),
        outputCreated: false
      });
    }
  }

  if (isTestMode()) {
    const track = fallbackTrack(kind, input);
    return {
      ok: true,
      skipped: false,
      outputCreated: true,
      providerAdapter: "stub",
      // Diagnostic marker for local/test fallback; not a real upstream API.
      providerEndpoint: "stub://media",
      providerRequestId: null,
      track: { ...track, providerAdapter: "stub", modelId: "music_v1" }
    };
  }

  const promptText = extractMusicPrompt(input);
  if (!promptText) {
    return skipResult({
      tool,
      input,
      provider: "elevenlabs_music",
      reason: "missing_music_prompt",
      detail: "Provide prompt or mood for score/music generation.",
      outputCreated: false
    });
  }

  if (!process.env.ELEVENLABS_API_KEY) {
    return skipResult({
      tool,
      input,
      provider: "none",
      reason: "no_music_provider",
      detail:
        "Set ELEVENLABS_API_KEY for ElevenLabs Music (compose API) or CINEFUSE_AUDIO_SCORE_PROVIDER_URL for a custom bridge. Persist MP3 via CINEFUSE_AUDIO_UPLOAD_URL, or rely on the API gateway to pass project file upload when CINEFUSE_GATEWAY_PUBLIC_ORIGIN is set.",
      outputCreated: false
    });
  }

  const tierCfg = resolveSoundTierConfig(input.modelTier ?? "budget");
  const musicLengthMs = Math.min(
    600_000,
    Math.max(3000, Number(input.durationMs ?? input.musicLengthMs ?? 30_000))
  );

  try {
    const { buffer, providerRequestId: elevenRequestId } = await elevenLabsComposeMusic({
      prompt: promptText,
      musicLengthMs,
      forceInstrumental: input.forceInstrumental !== false
    });
    const uploadFilename =
      typeof input.shotId === "string" && input.shotId.length > 0
        ? `sound-${input.shotId}.mp3`
        : `sound-${randomUUID()}.mp3`;
    const uploadedUrl = await uploadAudioBuffer(buffer, "audio/mpeg", {
      uploadUrl: typeof input.uploadUrl === "string" ? input.uploadUrl : undefined,
      authorizationHeader: typeof input.uploadAuthorization === "string"
        ? input.uploadAuthorization
        : undefined,
      uploadWorkerToken: typeof input.uploadWorkerToken === "string" ? input.uploadWorkerToken : undefined,
      uploadProjectId: typeof input.uploadProjectId === "string" ? input.uploadProjectId : undefined,
      uploadUserId: typeof input.uploadUserId === "string" ? input.uploadUserId : undefined,
      filename: uploadFilename
    });
    if (!uploadedUrl) {
      return skipResult({
        tool,
        input,
        provider: "elevenlabs_music",
        reason: "elevenlabs_music_requires_upload_url",
        detail:
          "ElevenLabs Music returned audio but no upload target is configured. Set CINEFUSE_AUDIO_UPLOAD_URL (and token if required), or set CINEFUSE_GATEWAY_PUBLIC_ORIGIN (or CINEFUSE_API_BASE_URL) plus CINEFUSE_WORKER_TOKEN on the gateway so ingest can POST to /api/v1/internal/render/project-audio.",
        outputCreated: false
      });
    }
    const track = normalizeTrack(
      {
        sourceUrl: uploadedUrl,
        durationMs: musicLengthMs,
        laneIndex: input.laneIndex,
        startMs: input.startMs,
        costToUsCents: tierCfg.costToUsCents,
        sparksCost: tierCfg.sparks
      },
      kind,
      input
    );
    return {
      ok: true,
      skipped: false,
      outputCreated: true,
      providerAdapter: "elevenlabs_music",
      providerEndpoint: "https://api.elevenlabs.io/v1/music",
      providerRequestId: elevenRequestId ?? null,
      track: {
        ...track,
        providerAdapter: "elevenlabs_music",
        modelId: "music_v1"
      }
    };
  } catch (err) {
    return skipResult({
      tool,
      input,
      provider: "elevenlabs_music",
      reason: "elevenlabs_music_failed",
      detail: err instanceof Error ? err.message : String(err),
      outputCreated: false
    });
  }
}

async function runHttpOrStubTool(tool, kind, input) {
  const httpUrl = resolveProviderUrl(tool);
  if (httpUrl) {
    try {
      const track = await callAudioProvider(tool, kind, input);
      return {
        ok: true,
        skipped: false,
        outputCreated: true,
        providerAdapter: resolveAudioAdapterKind(),
        track: {
          ...track,
          providerAdapter: resolveAudioAdapterKind()
        }
      };
    } catch (err) {
      return skipResult({
        tool,
        input,
        provider: "http_adapter",
        reason: "provider_call_failed",
        detail: err instanceof Error ? err.message : String(err),
        outputCreated: false
      });
    }
  }

  if (isTestMode()) {
    const track = fallbackTrack(kind, input);
    return {
      ok: true,
      skipped: false,
      outputCreated: true,
      providerAdapter: "stub",
      track: { ...track, providerAdapter: "stub" }
    };
  }

  return skipResult({
    tool,
    input,
    provider: "none",
    reason: "no_provider_configured",
    detail: `Set CINEFUSE_AUDIO_PROVIDER_URL or tool-specific URL for ${tool}.`,
    outputCreated: false
  });
}

export function createServer() {
  return {
    name: "audio",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input = {}) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      if (tool === "quote_sound") {
        const modelTier = input?.modelTier ?? "budget";
        const cfg = resolveSoundTierConfig(modelTier);
        return {
          ok: true,
          server: "audio",
          tool,
          modelTier,
          modelId: cfg.modelId,
          sparksCost: cfg.sparks,
          estimatedDurationSec: cfg.estimatedDurationSec,
          costToUsCents: cfg.costToUsCents
        };
      }
      if (tool === "lookup_sfx") {
        return {
          ok: true,
          server: "audio",
          tool,
          matches: [
            {
              id: "freesound-rain-bed",
              label: "Rain Ambience Bed",
              category: "atmos",
              sourceUrl: "https://cdn.freesound.org/previews/648/648816_1547956-lq.mp3"
            },
            {
              id: "freesound-door-slam",
              label: "Heavy Metal Door Slam",
              category: "impact",
              sourceUrl: "https://cdn.freesound.org/previews/725/725423_4019024-lq.mp3"
            }
          ]
        };
      }

      const kindByTool = {
        generate_dialogue: "dialogue",
        generate_score: "score",
        generate_sfx: "sfx",
        mix_scene: "mix",
        lipsync: "lipsync"
      };
      const kind = kindByTool[tool] ?? "audio";

      let result;
      if (tool === "generate_dialogue") {
        result = await runGenerateDialogue(tool, kind, input);
      } else if (tool === "generate_score") {
        result = await runGenerateScore(tool, kind, input);
      } else {
        result = await runHttpOrStubTool(tool, kind, input);
      }

      const adapter = result.providerAdapter
        ?? result.track?.providerAdapter
        ?? resolveAudioAdapterKind();

      return {
        ok: true,
        server: "audio",
        tool,
        adapter,
        providerEndpoint: result.providerEndpoint ?? null,
        providerRequestId: result.providerRequestId ?? null,
        skipped: Boolean(result.skipped),
        skippedFeature: result.skippedFeature ?? null,
        featureError: result.featureError ?? null,
        outputCreated: result.outputCreated !== false,
        track: result.track ?? null
      };
    }
  };
}
