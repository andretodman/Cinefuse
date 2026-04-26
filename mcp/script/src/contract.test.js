import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("script contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("revise_scene"), true);
  const result = await server.invoke("generate_beat_sheet", { logline: "test" });
  assert.equal(result.ok, true);
});

test("script contract: beat sheet generation is deterministic", async () => {
  const server = createServer();
  const first = await server.invoke("generate_beat_sheet", {
    logline: "A diver searches for a missing beacon.",
    tone: "Drama",
    targetDurationMinutes: 5
  });
  const second = await server.invoke("generate_beat_sheet", {
    logline: "A diver searches for a missing beacon.",
    tone: "Drama",
    targetDurationMinutes: 5
  });
  assert.equal(first.scenes.length, second.scenes.length);
  assert.equal(first.scenes[0].id, second.scenes[0].id);
});

test("script contract: revise_scene normalizes text fields", async () => {
  const server = createServer();
  const revised = await server.invoke("revise_scene", {
    sceneId: "scene_1",
    orderIndex: -9,
    title: "  Opening Beat ",
    revision: "   Diver prepares gear before sunrise.  ",
    mood: " THRILLER "
  });
  assert.equal(revised.scene.id, "scene_1");
  assert.equal(revised.scene.orderIndex, 0);
  assert.equal(revised.scene.title, "Opening Beat");
  assert.equal(revised.scene.description, "Diver prepares gear before sunrise.");
  assert.equal(revised.scene.mood, "thriller");
});
