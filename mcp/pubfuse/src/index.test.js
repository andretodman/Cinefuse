import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("pubfuse server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "pubfuse");
  assert.equal(server.listTools().includes("get_user"), true);
});
