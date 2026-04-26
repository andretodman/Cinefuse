import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("export contract: list_tools and invoke", async () => {
  const server = createServer();
  assert.equal(server.listTools().includes("archive_project"), true);
  const result = await server.invoke("encode_final", { projectId: "proj_1" });
  assert.equal(result.ok, true);
});
