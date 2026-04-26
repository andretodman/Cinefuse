import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const baseUrl = process.env.CINEFUSE_EVAL_BASE_URL ?? "http://localhost:4000";
const token = process.env.CINEFUSE_EVAL_BEARER ?? "user:eval_user";

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
  const promptsPath = path.join(__dirname, "clip-prompts.json");
  const prompts = JSON.parse(await fs.readFile(promptsPath, "utf8"));

  const project = await request("POST", "/api/v1/cinefuse/projects", {
    title: `Eval baseline ${new Date().toISOString()}`
  });
  const projectId = project.project.id;

  const rows = [];
  for (const item of prompts) {
    const quote = await request("POST", `/api/v1/cinefuse/projects/${projectId}/shots/quote`, {
      prompt: item.prompt,
      modelTier: item.modelTier
    });
    const shot = await request("POST", `/api/v1/cinefuse/projects/${projectId}/shots`, {
      prompt: item.prompt,
      modelTier: item.modelTier
    });
    const generate = await request(
      "POST",
      `/api/v1/cinefuse/projects/${projectId}/shots/${shot.shot.id}/generate`
    );
    let finalShot = generate.shot;
    let attempts = 0;
    while (attempts < 30 && finalShot.status !== "ready" && finalShot.status !== "failed") {
      attempts += 1;
      await new Promise((resolve) => setTimeout(resolve, 80));
      const listedShots = await request("GET", `/api/v1/cinefuse/projects/${projectId}/shots`);
      finalShot = listedShots.shots.find((entry) => entry.id === shot.shot.id) ?? finalShot;
    }
    const jobs = await request("GET", `/api/v1/cinefuse/projects/${projectId}/jobs`);
    const clipJob = jobs.jobs.find((entry) => entry.shotId === shot.shot.id && entry.kind === "clip");
    rows.push({
      id: item.id,
      modelTier: item.modelTier,
      sparksCost: quote.quote.sparksCost,
      estimatedDurationSec: quote.quote.estimatedDurationSec,
      shotStatus: finalShot.status,
      jobStatus: clipJob?.status ?? generate.job.status,
      costToUsCents: clipJob?.costToUsCents ?? 0
    });
  }

  const totals = rows.reduce(
    (acc, row) => {
      acc.sparks += row.sparksCost;
      return acc;
    },
    { sparks: 0 }
  );

  const markdown = [
    "# Clip Eval Baseline",
    "",
    `- Generated at: ${new Date().toISOString()}`,
    `- Base URL: ${baseUrl}`,
    `- Project ID: ${projectId}`,
    `- Prompt count: ${rows.length}`,
    `- Total sparks quoted: ${totals.sparks}`,
    "",
    "## Results",
    "",
    "| ID | Tier | Sparks | Duration(s) | Shot status | Job status | Cost to us (cents) |",
    "| --- | --- | ---: | ---: | --- | --- | ---: |",
    ...rows.map((row) => `| ${row.id} | ${row.modelTier} | ${row.sparksCost} | ${row.estimatedDurationSec ?? "-"} | ${row.shotStatus} | ${row.jobStatus} | ${row.costToUsCents} |`)
  ].join("\n");

  const outputDir = path.join(__dirname, "output");
  await fs.mkdir(outputDir, { recursive: true });
  const outputPath = path.join(outputDir, `clip-baseline-${Date.now()}.md`);
  await fs.writeFile(outputPath, markdown, "utf8");
  console.log(`Wrote ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
