import test from "node:test";
import assert from "node:assert/strict";
import { createHttpServer } from "./http-server.js";
import { clearProjects } from "./project-store.js";

function authHeaders(userId) {
  return {
    authorization: `Bearer user:${userId}`,
    "content-type": "application/json"
  };
}

test("api contract: create/list projects and get spark balance", async () => {
  const headers = authHeaders("usr_contract_projects");
  await clearProjects();
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
  assert.equal(balanceBody.balance, 99930);

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
  const headers = authHeaders("usr_contract_alias");
  await clearProjects();
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
  const headers = authHeaders("usr_contract_sparks");
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
  assert.equal(debitBody.balance, 99930);

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
  const headers = authHeaders("usr_contract_events");
  await clearProjects();
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

test("api contract: storyboard generation and scene revision", async () => {
  const headers = authHeaders("usr_contract_storyboard");
  await clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createProject = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Storyboard Project", logline: "A diver searches for a missing beacon." })
  });
  assert.equal(createProject.status, 201);
  const projectId = (await createProject.json()).project.id;

  const generate = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/storyboard/generate`, {
    method: "POST",
    headers
  });
  assert.equal(generate.status, 200);
  const generatedBody = await generate.json();
  assert.equal(Array.isArray(generatedBody.scenes), true);
  assert.equal(generatedBody.scenes.length >= 8, true);

  const sceneId = generatedBody.scenes[0].id;
  const revise = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/scenes/${sceneId}`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      title: "Revised Opening",
      revision: "The diver prepares gear in silence before sunrise.",
      orderIndex: 0
    })
  });
  assert.equal(revise.status, 200);
  const revisedBody = await revise.json();
  assert.equal(revisedBody.scene.title, "Revised Opening");

  const listScenes = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/scenes`, { headers });
  assert.equal(listScenes.status, 200);
  const scenesBody = await listScenes.json();
  assert.equal(scenesBody.scenes.length >= 8, true);

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

test("api contract: character create/train and shot lock", async () => {
  const headers = authHeaders("usr_contract_character");
  await clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createProject = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Character Project" })
  });
  assert.equal(createProject.status, 201);
  const projectId = (await createProject.json()).project.id;

  const createCharacter = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/characters`, {
    method: "POST",
    headers,
    body: JSON.stringify({ name: "Captain Mara", description: "Lead diver" })
  });
  assert.equal(createCharacter.status, 201);
  const characterId = (await createCharacter.json()).character.id;

  const trainCharacter = await fetch(
    `${baseUrl}/api/v1/cinefuse/projects/${projectId}/characters/${characterId}/train`,
    {
      method: "POST",
      headers
    }
  );
  assert.equal(trainCharacter.status, 200);
  const trainedBody = await trainCharacter.json();
  assert.equal(trainedBody.sparksCost, 500);
  assert.equal(trainedBody.character.consistencyPassed, true);
  assert.equal(typeof trainedBody.character.consistencyScore, "number");

  const balance = await fetch(`${baseUrl}/api/v1/cinefuse/sparks/balance`, { headers });
  assert.equal(balance.status, 200);
  const balanceBody = await balance.json();
  assert.equal(balanceBody.balance, 99500);

  const listCharacters = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/characters`, { headers });
  assert.equal(listCharacters.status, 200);
  const charactersBody = await listCharacters.json();
  assert.equal(charactersBody.characters.length, 1);
  assert.equal(charactersBody.characters[0].status, "trained");

  const createShot = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      prompt: "Close-up of Captain Mara checking oxygen gauge",
      modelTier: "standard",
      characterLocks: [characterId]
    })
  });
  assert.equal(createShot.status, 201);
  const shotBody = await createShot.json();
  assert.deepEqual(shotBody.shot.characterLocks, [characterId]);

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

test("api contract: timeline reorder and audio track persistence", async () => {
  const headers = authHeaders("usr_contract_timeline");
  await clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createProject = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Timeline Project" })
  });
  assert.equal(createProject.status, 201);
  const projectId = (await createProject.json()).project.id;

  const shotAResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
    method: "POST",
    headers,
    body: JSON.stringify({ prompt: "Shot A", modelTier: "budget" })
  });
  const shotA = (await shotAResponse.json()).shot;
  const shotBResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
    method: "POST",
    headers,
    body: JSON.stringify({ prompt: "Shot B", modelTier: "budget" })
  });
  const shotB = (await shotBResponse.json()).shot;

  const reorderResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/timeline/reorder`, {
    method: "PUT",
    headers,
    body: JSON.stringify({ shotIds: [shotB.id, shotA.id] })
  });
  assert.equal(reorderResponse.status, 200);

  const timelineResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/timeline`, { headers });
  assert.equal(timelineResponse.status, 200);
  const timelineBody = await timelineResponse.json();
  assert.equal(timelineBody.shots[0].id, shotB.id);
  assert.equal(timelineBody.shots[1].id, shotA.id);

  const createAudioTrack = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/audio-tracks`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      shotId: shotB.id,
      kind: "dialogue",
      title: "Captain line read",
      sourceUrl: "https://pubfuse.local/cinefuse/audio/dialogue.wav",
      laneIndex: 0,
      startMs: 0,
      durationMs: 4200,
      status: "ready"
    })
  });
  assert.equal(createAudioTrack.status, 201);

  const audioTracksResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/audio-tracks`, { headers });
  assert.equal(audioTracksResponse.status, 200);
  const tracksBody = await audioTracksResponse.json();
  assert.equal(tracksBody.audioTracks.length, 1);
  assert.equal(tracksBody.audioTracks[0].kind, "dialogue");

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

test("api contract: audio generation and final export flow", async () => {
  const headers = authHeaders("usr_contract_export");
  await clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createProject = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Export Project" })
  });
  assert.equal(createProject.status, 201);
  const projectId = (await createProject.json()).project.id;

  const createShot = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
    method: "POST",
    headers,
    body: JSON.stringify({ prompt: "Opening frame", modelTier: "standard" })
  });
  assert.equal(createShot.status, 201);
  const shotId = (await createShot.json()).shot.id;

  const dialogue = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/audio/dialogue`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      shotId,
      title: "Narration track",
      laneIndex: 0,
      startMs: 0,
      durationMs: 3500
    })
  });
  assert.equal(dialogue.status, 200);
  const dialogueBody = await dialogue.json();
  assert.equal(dialogueBody.audioTrack.kind, "dialogue");

  const exportResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/export/final`, {
    method: "POST",
    headers
  });
  assert.equal(exportResponse.status, 200);
  const exportBody = await exportResponse.json();
  assert.equal(exportBody.job.kind, "export");
  assert.match(exportBody.export.fileUrl, /^https:\/\/pubfuse\.local\/cinefuse\/exports\/.+\.mp4$/);

  const jobsResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/jobs`, { headers });
  const jobsBody = await jobsResponse.json();
  assert.equal(jobsBody.jobs.some((job) => job.kind === "audio"), true);
  assert.equal(jobsBody.jobs.some((job) => job.kind === "export"), true);

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
