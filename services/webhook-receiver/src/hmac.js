import { createHmac, timingSafeEqual } from "node:crypto";

export function computeSignature(secret, body) {
  return createHmac("sha256", secret).update(body).digest("hex");
}

export function verifySignature(secret, body, signature) {
  if (!signature) {
    return false;
  }
  const expected = computeSignature(secret, body);
  const expectedBuffer = Buffer.from(expected, "utf8");
  const incomingBuffer = Buffer.from(signature, "utf8");

  if (expectedBuffer.length !== incomingBuffer.length) {
    return false;
  }

  return timingSafeEqual(expectedBuffer, incomingBuffer);
}
