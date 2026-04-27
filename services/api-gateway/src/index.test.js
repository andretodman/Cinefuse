import test from "node:test";
import assert from "node:assert/strict";
import { parseBearerAuth } from "./auth.js";
import { createMcpHost } from "./mcp-host.js";

test("parseBearerAuth extracts user id", () => {
  const auth = parseBearerAuth("Bearer user:usr_1");
  assert.equal(auth?.userId, "usr_1");
});

test("parseBearerAuth extracts user id from jwt sub", () => {
  const payload = Buffer.from(JSON.stringify({ sub: "usr_jwt_1" }))
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
  const token = `header.${payload}.sig`;
  const auth = parseBearerAuth(`Bearer ${token}`);
  assert.equal(auth?.userId, "usr_jwt_1");
});

test("mcp host wires all m0 servers", () => {
  const host = createMcpHost();
  const servers = host.listServers();
  assert.equal(servers.includes("pubfuse"), true);
  assert.equal(servers.includes("billing"), true);
  assert.equal(servers.includes("export"), true);
});
