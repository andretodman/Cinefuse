import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("export server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "export");
  assert.equal(server.listTools().includes("encode_final"), true);
  assert.equal(server.listTools().includes("encode_audio_mixdown"), true);
});
