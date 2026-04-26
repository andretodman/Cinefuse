import test from "node:test";
import assert from "node:assert/strict";
import { createWebhookServer } from "./index.js";
import { computeSignature } from "./hmac.js";

test("webhook contract: rejects bad signature, accepts valid signature", async () => {
  process.env.PUBFUSE_HMAC_SECRET = "contract-secret";
  const server = createWebhookServer();

  await new Promise((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;
  const body = JSON.stringify({ event: "user.deleted" });

  const badResponse = await fetch(`${baseUrl}/webhooks/pubfuse`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-pubfuse-signature": "bad"
    },
    body
  });
  assert.equal(badResponse.status, 401);

  const validSignature = computeSignature("contract-secret", body);
  const okResponse = await fetch(`${baseUrl}/webhooks/pubfuse`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-pubfuse-signature": validSignature
    },
    body
  });
  assert.equal(okResponse.status, 200);

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
