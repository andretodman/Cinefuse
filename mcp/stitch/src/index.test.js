import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("stitch server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "stitch");
  assert.equal(server.listTools().includes("preview_stitch"), true);
});
