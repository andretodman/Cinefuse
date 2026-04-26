import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "./server.js";

test("billing contract: list_tools and invoke", async () => {
  const server = createServer(100000);
  const tools = server.listTools();
  assert.equal(tools.includes("get_balance"), true);

  const result = await server.invoke("get_balance", { userId: "usr_1" });
  assert.equal(result.ok, true);
  assert.equal(result.balance, 100000);
});
