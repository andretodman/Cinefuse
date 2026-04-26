import test from "node:test";
import assert from "node:assert/strict";
import { createPubfuseClient } from "./index.js";

test("createPubfuseClient returns required methods", () => {
  const client = createPubfuseClient({
    baseUrl: "https://api.pubfuse.com",
    appId: "Cinefuse",
    clientId: "id",
    clientSecret: "secret"
  });

  assert.equal(typeof client.getUser, "function");
  assert.equal(typeof client.getBalance, "function");
});
