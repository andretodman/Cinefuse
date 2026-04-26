import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const baseUrl = process.env.CINEFUSE_EVAL_BASE_URL ?? "http://localhost:4000";
const token = process.env.CINEFUSE_EVAL_BEARER ?? "user:eval_export";

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
    title: `Export eval ${new Date().toISOString()}`
  });
  const projectId = project.project.id;
  await request("POST", `/api/v1/cinefuse/projects/${projectId}/shots`, {
    prompt: "Wide establishing sunset shot",
    modelTier: "standard"
  });
  await request("POST", `/api/v1/cinefuse/projects/${projectId}/audio/score`, {
    title: "Score bed",
    laneIndex: 1,
    startMs: 0,
    durationMs: 5000
  });

  const exported = await request("POST", `/api/v1/cinefuse/projects/${projectId}/export/final`);
  const jobs = await request("GET", `/api/v1/cinefuse/projects/${projectId}/jobs`);

  const markdown = [
    "# Export Eval Baseline",
    "",
    `- Generated at: ${new Date().toISOString()}`,
    `- Project ID: ${projectId}`,
    `- Export file: ${exported.export.fileUrl}`,
    `- Archive file: ${exported.export.archiveUrl}`,
    `- Export job status: ${exported.job.status}`,
    `- Job count: ${jobs.jobs.length}`,
    ""
  ].join("\n");

  const outputDir = path.join(__dirname, "output");
  await fs.mkdir(outputDir, { recursive: true });
  const outputPath = path.join(outputDir, `export-baseline-${Date.now()}.md`);
  await fs.writeFile(outputPath, markdown, "utf8");
  console.log(`Wrote ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
