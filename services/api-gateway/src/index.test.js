import test from "node:test";
import assert from "node:assert/strict";
import { parseBearerAuth } from "./auth.js";
import { createMcpHost } from "./mcp-host.js";

test("parseBearerAuth extracts user id", () => {
  const auth = parseBearerAuth("Bearer user:usr_1");
  assert.equal(auth?.userId, "usr_1");
});

test("mcp host wires all m0 servers", () => {
  const host = createMcpHost();
  const servers = host.listServers();
  assert.equal(servers.includes("pubfuse"), true);
  assert.equal(servers.includes("billing"), true);
  assert.equal(servers.includes("export"), true);
});
