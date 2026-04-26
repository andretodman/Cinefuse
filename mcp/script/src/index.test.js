import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("script server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "script");
  assert.equal(server.listTools().includes("generate_beat_sheet"), true);
});
