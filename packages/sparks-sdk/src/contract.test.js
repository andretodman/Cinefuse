import test from "node:test";
import assert from "node:assert/strict";
import { createPubfuseClient } from "./index.js";

test("sdk exposes stable pubfuse methods", () => {
  const client = createPubfuseClient({
    baseUrl: "https://api.pubfuse.com",
    appId: "Cinefuse",
    clientId: "id",
    clientSecret: "secret"
  });

  assert.deepEqual(Object.keys(client).sort(), ["getBalance", "getUser"]);
});
