import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const baseUrl = process.env.CINEFUSE_EVAL_BASE_URL ?? "http://localhost:4000";
const token = process.env.CINEFUSE_EVAL_BEARER ?? "user:eval_script";

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
    title: `Script eval ${new Date().toISOString()}`,
    logline: "A diver searches for a missing beacon in dangerous waters."
  });
  const projectId = project.project.id;

  const first = await request("POST", `/api/v1/cinefuse/projects/${projectId}/storyboard/generate`);
  const second = await request("POST", `/api/v1/cinefuse/projects/${projectId}/storyboard/generate`);
  const sceneIdStable = first.scenes[0]?.id === second.scenes[0]?.id;

  const revised = await request("POST", `/api/v1/cinefuse/projects/${projectId}/scenes/${first.scenes[0].id}`, {
    title: "Revised opening beat",
    revision: "Diver prepares gear before sunrise and checks oxygen pressure.",
    orderIndex: 0
  });

  const markdown = [
    "# Script Eval Baseline",
    "",
    `- Generated at: ${new Date().toISOString()}`,
    `- Base URL: ${baseUrl}`,
    `- Project ID: ${projectId}`,
    `- Scene count: ${first.scenes.length}`,
    `- Stable first scene ID across regenerate: ${sceneIdStable}`,
    `- Revised first scene title: ${revised.scene.title}`,
    ""
  ].join("\n");

  const outputDir = path.join(__dirname, "output");
  await fs.mkdir(outputDir, { recursive: true });
  const outputPath = path.join(outputDir, `script-baseline-${Date.now()}.md`);
  await fs.writeFile(outputPath, markdown, "utf8");
  console.log(`Wrote ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
