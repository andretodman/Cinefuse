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
  assert.equal(generateBody.job.progressPct, 0);
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
  assert.match(shotClipUrl, /^https:\/\/.+\.mp4$/);

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
  const generatedClipJob = jobsBody.jobs.find((job) => job.kind === "clip" && job.shotId === shotId);
  assert.ok(generatedClipJob);
  assert.equal(typeof generatedClipJob.progressPct === "number", true);
  if (generatedClipJob.status === "done") {
    assert.equal(generatedClipJob.costToUsCents > 0, true);
  }

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

test("api contract: rename project and retry/delete failed shot/job", async () => {
  const headers = authHeaders("usr_contract_recovery");
  await clearProjects();
  const server = createHttpServer();
  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createProjectResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Recovery Project" })
  });
  assert.equal(createProjectResponse.status, 201);
  const projectId = (await createProjectResponse.json()).project.id;

  const renameResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}`, {
    method: "PATCH",
    headers,
    body: JSON.stringify({ title: "Renamed Recovery Project" })
  });
  assert.equal(renameResponse.status, 200);
  const renamedBody = await renameResponse.json();
  assert.equal(renamedBody.project.title, "Renamed Recovery Project");

  const createFailedShotResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
    method: "POST",
    headers,
    body: JSON.stringify({ prompt: "stormy skyline", modelTier: "budget", status: "failed" })
  });
  assert.equal(createFailedShotResponse.status, 201);
  const failedShot = (await createFailedShotResponse.json()).shot;

  const retryShotResponse = await fetch(
    `${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots/${failedShot.id}/retry`,
    { method: "POST", headers }
  );
  assert.equal(retryShotResponse.status, 200);
  const retryShotBody = await retryShotResponse.json();
  assert.equal(retryShotBody.shot.status, "queued");
  assert.equal(retryShotBody.job.status, "queued");
  assert.equal(retryShotBody.job.progressPct, 0);

  const createFailedJobResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/jobs`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      kind: "clip",
      shotId: failedShot.id,
      status: "failed",
      progressPct: 0
    })
  });
  assert.equal(createFailedJobResponse.status, 201);
  const failedJobId = (await createFailedJobResponse.json()).job.id;

  const retryJobResponse = await fetch(
    `${baseUrl}/api/v1/cinefuse/projects/${projectId}/jobs/${failedJobId}/retry`,
    { method: "POST", headers }
  );
  assert.equal(retryJobResponse.status, 200);
  const retryJobBody = await retryJobResponse.json();
  assert.equal(retryJobBody.job.status, "queued");
  assert.equal(retryJobBody.job.progressPct, 0);

  const deleteJobResponse = await fetch(
    `${baseUrl}/api/v1/cinefuse/projects/${projectId}/jobs/${failedJobId}`,
    { method: "DELETE", headers }
  );
  assert.equal(deleteJobResponse.status, 200);

  const deleteShotResponse = await fetch(
    `${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots/${failedShot.id}`,
    { method: "DELETE", headers }
  );
  assert.equal(deleteShotResponse.status, 200);

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

test("api contract: ownership is scoped to authenticated user id", async () => {
  await clearProjects();
  const server = createHttpServer();
  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;
  const ownerAHeaders = authHeaders("owner_a");
  const ownerBHeaders = authHeaders("owner_b");

  const createResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers: ownerAHeaders,
    body: JSON.stringify({ title: "Owner A Project" })
  });
  assert.equal(createResponse.status, 201);

  const listA = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, { headers: ownerAHeaders });
  const bodyA = await listA.json();
  assert.equal(bodyA.projects.length, 1);
  assert.equal(bodyA.projects[0].ownerUserId, "owner_a");

  const listB = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, { headers: ownerBHeaders });
  const bodyB = await listB.json();
  assert.equal(bodyB.projects.length, 0);

  const malformedAuth = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    headers: { authorization: "Bearer user:bad id", "content-type": "application/json" }
  });
  assert.equal(malformedAuth.status, 401);

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
  const sceneCountAfterFirstGeneration = scenesBody.scenes.length;

  const regenerate = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/storyboard/generate`, {
    method: "POST",
    headers
  });
  assert.equal(regenerate.status, 200);
  const regenerateBody = await regenerate.json();
  assert.equal(regenerateBody.scenes[0].id, generatedBody.scenes[0].id);

  const listScenesAfterRegenerate = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/scenes`, { headers });
  const scenesAfterRegenerate = await listScenesAfterRegenerate.json();
  assert.equal(scenesAfterRegenerate.scenes.length, sceneCountAfterFirstGeneration);

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

  const sfx = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/audio/sfx`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      title: "Door slam",
      laneIndex: 2,
      startMs: 1000,
      durationMs: 1200
    })
  });
  assert.equal(sfx.status, 200);
  const sfxBody = await sfx.json();
  assert.equal(sfxBody.audioTrack.kind, "sfx");

  const mix = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/audio/mix`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      title: "Scene 1 mix",
      laneIndex: 3,
      startMs: 0,
      durationMs: 4500
    })
  });
  assert.equal(mix.status, 200);
  const mixBody = await mix.json();
  assert.equal(mixBody.audioTrack.kind, "mix");

  const lipsync = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/audio/lipsync`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      shotId,
      title: "Lip-sync pass",
      laneIndex: 0,
      startMs: 0,
      durationMs: 3500
    })
  });
  assert.equal(lipsync.status, 200);
  const lipsyncBody = await lipsync.json();
  assert.equal(lipsyncBody.audioTrack.kind, "lipsync");

  const stitchPreview = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/stitch/preview`, {
    method: "POST",
    headers,
    body: JSON.stringify({ transitionStyle: "crossfade", captionsEnabled: true })
  });
  assert.equal(stitchPreview.status, 200);
  const stitchPreviewBody = await stitchPreview.json();
  assert.equal(stitchPreviewBody.stitch.kind, "preview_stitch");

  const stitchTransitions = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/stitch/transitions`, {
    method: "POST",
    headers,
    body: JSON.stringify({ transitionStyle: "dip_to_black" })
  });
  assert.equal(stitchTransitions.status, 200);
  const stitchTransitionsBody = await stitchTransitions.json();
  assert.equal(stitchTransitionsBody.stitch.kind, "apply_transitions");

  const stitchColor = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/stitch/color-match`, {
    method: "POST",
    headers,
    body: JSON.stringify({ colorMatchMode: "balanced" })
  });
  assert.equal(stitchColor.status, 200);
  const stitchColorBody = await stitchColor.json();
  assert.equal(stitchColorBody.stitch.kind, "color_match");

  const stitchCaptions = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/stitch/captions/bake`, {
    method: "POST",
    headers,
    body: JSON.stringify({ captionsEnabled: true })
  });
  assert.equal(stitchCaptions.status, 200);
  const stitchCaptionsBody = await stitchCaptions.json();
  assert.equal(stitchCaptionsBody.stitch.kind, "bake_captions");

  const stitchLoudness = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/stitch/loudness/normalize`, {
    method: "POST",
    headers,
    body: JSON.stringify({ targetLufs: -14 })
  });
  assert.equal(stitchLoudness.status, 200);
  const stitchLoudnessBody = await stitchLoudness.json();
  assert.equal(stitchLoudnessBody.stitch.kind, "loudness_normalize");

  const stitchFinal = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/stitch/final`, {
    method: "POST",
    headers,
    body: JSON.stringify({ transitionStyle: "crossfade", captionsEnabled: true, resolution: "1080p" })
  });
  assert.equal(stitchFinal.status, 200);
  const stitchFinalBody = await stitchFinal.json();
  assert.equal(stitchFinalBody.stitch.kind, "final_stitch");

  const exportResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/export/final`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      resolution: "4k",
      captionsEnabled: true,
      includeArchive: true,
      publishTarget: "pubfuse"
    })
  });
  assert.equal(exportResponse.status, 200);
  const exportBody = await exportResponse.json();
  assert.equal(exportBody.job.kind, "export");
  assert.match(exportBody.export.fileUrl, /^https:\/\/.+\.mp4$/);
  assert.equal(exportBody.archive !== null, true);
  assert.equal(exportBody.published !== null, true);

  const jobsResponse = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/jobs`, { headers });
  const jobsBody = await jobsResponse.json();
  assert.equal(jobsBody.jobs.filter((job) => job.kind === "audio").length >= 4, true);
  assert.equal(jobsBody.jobs.filter((job) => job.kind === "stitch").length >= 6, true);
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

test("api contract: clip generation debit is idempotent with caller key", async () => {
  const headers = authHeaders("usr_contract_clip_idempotent");
  await clearProjects();
  const server = createHttpServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const createProject = await fetch(`${baseUrl}/api/v1/cinefuse/projects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "Idempotent Clip Project" })
  });
  const projectId = (await createProject.json()).project.id;
  const createShot = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, {
    method: "POST",
    headers,
    body: JSON.stringify({ prompt: "Idempotent generation shot", modelTier: "standard" })
  });
  const shotId = (await createShot.json()).shot.id;
  const requestKey = `shot-request:${shotId}`;

  const firstGenerate = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots/${shotId}/generate`, {
    method: "POST",
    headers,
    body: JSON.stringify({ idempotencyKey: requestKey })
  });
  assert.equal(firstGenerate.status, 200);

  let retries = 30;
  while (retries > 0) {
    const listedShots = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots`, { headers });
    const shot = (await listedShots.json()).shots.find((entry) => entry.id === shotId);
    if (shot?.status === "ready" || shot?.status === "failed") {
      break;
    }
    retries -= 1;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }

  const secondGenerate = await fetch(`${baseUrl}/api/v1/cinefuse/projects/${projectId}/shots/${shotId}/generate`, {
    method: "POST",
    headers,
    body: JSON.stringify({ idempotencyKey: requestKey })
  });
  assert.equal(secondGenerate.status, 200);

  const balanceResponse = await fetch(`${baseUrl}/api/v1/cinefuse/sparks/balance`, { headers });
  const balanceBody = await balanceResponse.json();
  // Project create = 0 debit, generation quote for standard = 70, repeated request with same idempotency key should not double-charge.
  assert.equal(balanceBody.balance, 99930);

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
