import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("clip contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("generate_clip"), true);
  const result = await server.invoke("quote_clip", { tier: "standard", duration: 5 });
  assert.equal(result.ok, true);
});
