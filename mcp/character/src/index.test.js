import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("character server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "character");
  assert.equal(server.listTools().includes("create_character"), true);
});
