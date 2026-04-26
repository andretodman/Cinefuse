import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const baseUrl = process.env.CINEFUSE_EVAL_BASE_URL ?? "http://localhost:4000";
const token = process.env.CINEFUSE_EVAL_BEARER ?? "user:eval_character";

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
    title: `Character eval ${new Date().toISOString()}`,
    logline: "A deep-sea team searching for a missing beacon."
  });
  const projectId = project.project.id;

  const character = await request("POST", `/api/v1/cinefuse/projects/${projectId}/characters`, {
    name: "Captain Mara",
    description: "Lead diver and mission commander"
  });

  const trained = await request(
    "POST",
    `/api/v1/cinefuse/projects/${projectId}/characters/${character.character.id}/train`
  );

  const shot = await request("POST", `/api/v1/cinefuse/projects/${projectId}/shots`, {
    prompt: "Close-up of Captain Mara checking oxygen gauge before descent.",
    modelTier: "standard",
    characterLocks: [character.character.id]
  });

  const markdown = [
    "# Character Eval Baseline",
    "",
    `- Generated at: ${new Date().toISOString()}`,
    `- Base URL: ${baseUrl}`,
    `- Project ID: ${projectId}`,
    `- Character ID: ${character.character.id}`,
    `- Training status: ${trained.character.status}`,
    `- Training sparks cost: ${trained.sparksCost}`,
    `- Consistency score: ${trained.character.consistencyScore ?? "n/a"}`,
    `- Consistency threshold: ${trained.character.consistencyThreshold ?? "n/a"}`,
    `- Consistency passed: ${trained.character.consistencyPassed ?? false}`,
    `- Shot lock count: ${(shot.shot.characterLocks ?? []).length}`,
    `- Shot status: ${shot.shot.status}`,
    ""
  ].join("\n");

  const outputDir = path.join(__dirname, "output");
  await fs.mkdir(outputDir, { recursive: true });
  const outputPath = path.join(outputDir, `character-baseline-${Date.now()}.md`);
  await fs.writeFile(outputPath, markdown, "utf8");
  console.log(`Wrote ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
