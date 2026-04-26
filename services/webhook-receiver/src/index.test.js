import test from "node:test";
import assert from "node:assert/strict";
import { computeSignature, verifySignature } from "./hmac.js";

test("hmac verifier accepts valid signature", () => {
  const secret = "secret";
  const body = JSON.stringify({ event: "test" });
  const signature = computeSignature(secret, body);
  assert.equal(verifySignature(secret, body, signature), true);
});

test("hmac verifier rejects invalid signature", () => {
  assert.equal(verifySignature("secret", "{}", "invalid"), false);
});
