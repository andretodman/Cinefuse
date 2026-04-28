import test from "node:test";
import assert from "node:assert/strict";
import { parseBearerAuth } from "./auth.js";
import { createMcpHost } from "./mcp-host.js";
import { createHttpServer } from "./http-server.js";

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

test("public site routes serve html without auth", async () => {
  const server = createHttpServer();
  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const home = await fetch(`${baseUrl}/`);
  assert.equal(home.status, 200);
  assert.match(home.headers.get("content-type") ?? "", /text\/html/);
  const homeText = await home.text();
  assert.equal(homeText.includes("Generate, edit, and export cinematic clips."), true);

  const docs = await fetch(`${baseUrl}/docs`);
  assert.equal(docs.status, 200);
  assert.match(docs.headers.get("content-type") ?? "", /text\/html/);
  const docsText = await docs.text();
  assert.equal(docsText.includes("Cinefuse Docs"), true);

  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
});
