import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("clip server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "clip");
  assert.equal(server.listTools().includes("quote_clip"), true);
});
