import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("billing server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "billing");
  assert.equal(server.listTools().includes("debit"), true);
});
