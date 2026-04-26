import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const baseUrl = process.env.CINEFUSE_EVAL_BASE_URL ?? "http://localhost:4000";
const token = process.env.CINEFUSE_EVAL_BEARER ?? "user:eval_audio";

async function request(method, pathname, body) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(`${method} ${pathname} failed (${response.status}): ${JSON.stringify(data)}`);
  }
  return data;
}

async function main() {
  const project = await request("POST", "/api/v1/cinefuse/projects", {
    title: `Audio eval ${new Date().toISOString()}`
  });
  const projectId = project.project.id;
  const shot = await request("POST", `/api/v1/cinefuse/projects/${projectId}/shots`, {
    prompt: "A close shot with quiet narration",
    modelTier: "standard"
  });

  const dialogue = await request("POST", `/api/v1/cinefuse/projects/${projectId}/audio/dialogue`, {
    shotId: shot.shot.id,
    title: "Narrator line",
    laneIndex: 0,
    startMs: 0,
    durationMs: 3200
  });
  const score = await request("POST", `/api/v1/cinefuse/projects/${projectId}/audio/score`, {
    title: "Ambient score",
    laneIndex: 1,
    startMs: 0,
    durationMs: 10000
  });

  const tracks = await request("GET", `/api/v1/cinefuse/projects/${projectId}/audio-tracks`);

  const markdown = [
    "# Audio Eval Baseline",
    "",
    `- Generated at: ${new Date().toISOString()}`,
    `- Project ID: ${projectId}`,
    `- Dialogue track: ${dialogue.audioTrack.id}`,
    `- Score track: ${score.audioTrack.id}`,
    `- Track count: ${tracks.audioTracks.length}`,
    ""
  ].join("\n");

  const outputDir = path.join(__dirname, "output");
  await fs.mkdir(outputDir, { recursive: true });
  const outputPath = path.join(outputDir, `audio-baseline-${Date.now()}.md`);
  await fs.writeFile(outputPath, markdown, "utf8");
  console.log(`Wrote ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
