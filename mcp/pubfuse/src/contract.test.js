import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("pubfuse contract: list_tools and invoke", async () => {
  const server = createServer();
  const tools = server.listTools();
  assert.equal(Array.isArray(tools), true);
  assert.equal(tools.includes("get_user"), true);

  const result = await server.invoke("get_user", { userId: "usr_1" });
  assert.equal(result.ok, true);
  assert.equal(result.server, "pubfuse");
});
