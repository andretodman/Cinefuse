import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("audio server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "audio");
  assert.equal(server.listTools().includes("mix_scene"), true);
});
