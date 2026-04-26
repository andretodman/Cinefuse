import test from "node:test";
import assert from "node:assert/strict";
import { createHttpServer } from "./http-server.js";
import { clearProjects } from "./project-store.js";

const headers = {
  authorization: "Bearer user:usr_contract",
  "content-type": "application/json"
};

test("api contract: create/list projects and get spark balance", async () => {
  clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "M0 Contract Project" })
  });
  assert.equal(createResponse.status, 201);
  const createBody = await createResponse.json();
  const projectId = createBody.project.id;

  const listResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, { headers });
  assert.equal(listResponse.status, 200);
  const listBody = await listResponse.json();
  assert.equal(listBody.projects.length, 1);

  const shotCreateResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
    method: "POST",
    headers,
    body: JSON.stringify({ prompt: "wide lighthouse shot", modelTier: "standard" })
  });
  assert.equal(shotCreateResponse.status, 201);
  const shotCreateBody = await shotCreateResponse.json();
  const shotId = shotCreateBody.shot.id;

  const quoteResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots/quote`, {
    method: "POST",
    headers,
    body: JSON.stringify({ prompt: "wide lighthouse shot", modelTier: "standard" })
  });
  assert.equal(quoteResponse.status, 200);
  const quoteBody = await quoteResponse.json();
  assert.equal(quoteBody.quote.sparksCost, 70);
  assert.equal(quoteBody.quote.modelTier, "standard");

  const generateResponse = await fetch(
    `${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots/${shotId}/generate`,
    {
      method: "POST",
      headers
    }
  );
  assert.equal(generateResponse.status, 200);
  const generateBody = await generateResponse.json();
  assert.equal(generateBody.shot.status, "queued");
  assert.equal(generateBody.shot.clipUrl, null);
  assert.equal(generateBody.job.status, "queued");
  assert.equal(generateBody.quote.sparksCost, 70);

  let shotStatus = "queued";
  let shotClipUrl = null;
  let retries = 20;
  while (retries > 0) {
    const shotListResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
      headers
    });
    assert.equal(shotListResponse.status, 200);
    const shotsBody = await shotListResponse.json();
    assert.equal(shotsBody.shots.length, 1);
    shotStatus = shotsBody.shots[0].status;
    shotClipUrl = shotsBody.shots[0].clipUrl;
    if (shotStatus === "ready") {
      break;
    }
    retries -= 1;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.equal(shotStatus, "ready");
  assert.match(shotClipUrl, /^https:\/\/pubfuse\.local\/cinefuse\/clips\/.+\.mp4$/);

  const jobCreateResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/jobs`, {
    method: "POST",
    headers,
    body: JSON.stringify({ kind: "clip", inputPayload: { tier: "standard" } })
  });
  assert.equal(jobCreateResponse.status, 201);

  const jobListResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/jobs`, {
    headers
  });
  assert.equal(jobListResponse.status, 200);
  const jobsBody = await jobListResponse.json();
  assert.equal(jobsBody.jobs.length, 2);
  assert.equal(
    jobsBody.jobs.some((job) => job.kind === "clip" && (job.status === "queued" || job.status === "running" || job.status === "done")),
    true
  );

  const balanceResponse = await fetch(`${baseUrl}/api/v1/cinefuse/sparks/balance`, { headers });
  assert.equal(balanceResponse.status, 200);
  const balanceBody = await balanceResponse.json();
  assert.equal(balanceBody.balance, 100000);

  const deleteResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}`, {
    method: "DELETE",
    headers
  });
  assert.equal(deleteResponse.status, 200);

  const listAfterDelete = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, { headers });
  assert.equal(listAfterDelete.status, 200);
  const listAfterDeleteBody = await listAfterDelete.json();
  assert.equal(listAfterDeleteBody.projects.length, 0);

  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
});

test("api contract: /v1/projects alias maps to canonical route with deprecation headers", async () => {
  clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createResponse = await fetch(`${baseUrl}/v1/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Legacy route project" })
  });
  assert.equal(createResponse.status, 201);
  assert.equal(createResponse.headers.get("x-cinefuse-deprecated-route"), "/v1/projects");
  assert.equal(createResponse.headers.get("x-cinefuse-canonical-route"), "/api/v1/cinefuse/projects");

  const listResponse = await fetch(`${baseUrl}/v1/projects`, { headers });
  assert.equal(listResponse.status, 200);
  const listBody = await listResponse.json();
  assert.equal(listBody.projects.length, 1);

  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
});

test("api contract: spark canonical debit/credit and legacy balance alias", async () => {
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const debitResponse = await fetch(`${baseUrl}/api/v1/cinefuse/sparks/debit`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      amount: 70,
      idempotencyKey: "shot:abc123",
      relatedResourceType: "shot",
      relatedResourceId: "abc123"
    })
  });
  assert.equal(debitResponse.status, 200);
  const debitBody = await debitResponse.json();
  assert.equal(debitBody.ok, true);
  assert.equal(debitBody.transaction.kind, "debit");
  assert.equal(debitBody.transaction.amount, 70);
  assert.equal(debitBody.balance, 100000);

  const creditResponse = await fetch(`${baseUrl}/api/v1/cinefuse/sparks/credit`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      amount: 70,
      idempotencyKey: "refund:abc123",
      relatedResourceType: "shot",
      relatedResourceId: "abc123"
    })
  });
  assert.equal(creditResponse.status, 200);
  const creditBody = await creditResponse.json();
  assert.equal(creditBody.ok, true);
  assert.equal(creditBody.transaction.kind, "credit");
  assert.equal(creditBody.transaction.amount, 70);
  assert.equal(creditBody.balance, 100000);

  const legacyBalanceResponse = await fetch(`${baseUrl}/v1/sparks/balance`, { headers });
  assert.equal(legacyBalanceResponse.status, 200);
  assert.equal(legacyBalanceResponse.headers.get("x-cinefuse-deprecated-route"), "/v1/sparks/balance");
  assert.equal(
    legacyBalanceResponse.headers.get("x-cinefuse-canonical-route"),
    "/api/v1/cinefuse/sparks/balance"
  );

  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
});

test("api contract: project events stream is available", async () => {
  clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Events project" })
  });
  assert.equal(createResponse.status, 201);
  const createBody = await createResponse.json();
  const projectId = createBody.project.id;

  const streamResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/events`, {
    headers
  });
  assert.equal(streamResponse.status, 200);
  assert.equal(streamResponse.headers.get("content-type"), "text/event-stream");

  const reader = streamResponse.body?.getReader();
  assert.ok(reader);
  const firstChunk = await reader.read();
  assert.equal(firstChunk.done, false);
  const firstText = new TextDecoder().decode(firstChunk.value);
  assert.match(firstText, /"type":"connected"/);
  await reader.cancel();

  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
});
