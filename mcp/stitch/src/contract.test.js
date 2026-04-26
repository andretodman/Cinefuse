import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("stitch contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("final_stitch"), true);
  const result = await server.invoke("preview_stitch", { projectId: "proj_1" });
  assert.equal(result.ok, true);
});
