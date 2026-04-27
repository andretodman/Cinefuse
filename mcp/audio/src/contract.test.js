import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

process.env.CINEFUSE_ALLOW_STUB_MEDIA = "true";

test("audio contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("generate_dialogue"), true);
  const result = await server.invoke("generate_score", { mood: "tense" });
  assert.equal(result.ok, true);
});
