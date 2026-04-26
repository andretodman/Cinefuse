import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("character contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("train_identity"), true);
  const result = await server.invoke("create_character", { name: "Ari" });
  assert.equal(result.ok, true);
});
