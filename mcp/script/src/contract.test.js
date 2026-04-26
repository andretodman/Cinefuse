import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("script contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("revise_scene"), true);
  const result = await server.invoke("generate_beat_sheet", { logline: "test" });
  assert.equal(result.ok, true);
});
