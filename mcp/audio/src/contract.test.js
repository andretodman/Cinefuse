import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

process.env.CINEFUSE_ALLOW_STUB_MEDIA = "true";

test("audio contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("generate_dialogue"), true);
  assert.equal(server.listTools().includes("quote_sound"), true);
  const quote = await server.invoke("quote_sound", { modelTier: "standard" });
  assert.equal(quote.ok, true);
  assert.equal(quote.sparksCost, 70);
  assert.equal(quote.modelId, "music_v1");
  const result = await server.invoke("generate_score", { mood: "tense" });
  assert.equal(result.ok, true);
  assert.equal(result.adapter, "stub");
  assert.equal(typeof result.providerEndpoint, "string");
  assert.ok(result.providerEndpoint.length > 0);
  assert.equal(result.providerRequestId, null);
});
