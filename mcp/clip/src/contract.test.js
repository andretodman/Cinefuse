import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("clip contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("generate_clip"), true);
  const result = await server.invoke("quote_clip", { tier: "standard", duration: 5 });
  assert.equal(result.ok, true);
});

test("clip contract: generate returns cost and clip output", async () => {
  const server = createServer();
  const result = await server.invoke("generate_clip", {
    shotId: "shot_contract_1",
    modelTier: "standard",
    prompt: "Wide drone shot over city skyline"
  });
  assert.equal(result.ok, true);
  assert.equal(result.status, "ready");
  assert.equal(typeof result.costToUsCents, "number");
  assert.equal(typeof result.clipUrl, "string");
  assert.equal(result.clipUrl.length > 0, true);
});
