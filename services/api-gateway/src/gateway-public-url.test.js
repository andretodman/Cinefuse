import test from "node:test";
import assert from "node:assert/strict";
import {
  gatewayPublicOriginFromEnv,
  projectFilePublicUrl,
  resolvedGatewayPublicBase
} from "./gateway-public-url.js";

test("gatewayPublicOriginFromEnv prefers GATEWAY_PUBLIC_ORIGIN over API_BASE_URL", () => {
  const prevG = process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  const prevA = process.env.CINEFUSE_API_BASE_URL;
  process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN = "https://a.example.com/";
  process.env.CINEFUSE_API_BASE_URL = "https://b.example.com";
  assert.equal(gatewayPublicOriginFromEnv(), "https://a.example.com");
  if (prevG === undefined) {
    delete process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  } else {
    process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN = prevG;
  }
  if (prevA === undefined) {
    delete process.env.CINEFUSE_API_BASE_URL;
  } else {
    process.env.CINEFUSE_API_BASE_URL = prevA;
  }
});

test("gatewayPublicOriginFromEnv falls back to CINEFUSE_API_BASE_URL", () => {
  const prevG = process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  const prevA = process.env.CINEFUSE_API_BASE_URL;
  delete process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  process.env.CINEFUSE_API_BASE_URL = "http://localhost:4000/";
  assert.equal(gatewayPublicOriginFromEnv(), "http://localhost:4000");
  if (prevG === undefined) {
    delete process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  } else {
    process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN = prevG;
  }
  if (prevA === undefined) {
    delete process.env.CINEFUSE_API_BASE_URL;
  } else {
    process.env.CINEFUSE_API_BASE_URL = prevA;
  }
});

test("resolvedGatewayPublicBase uses Host when env empty", () => {
  const prevG = process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  const prevA = process.env.CINEFUSE_API_BASE_URL;
  delete process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  delete process.env.CINEFUSE_API_BASE_URL;
  assert.equal(
    resolvedGatewayPublicBase({
      headers: { host: "cinefuse.pubfuse.com" }
    }),
    "https://cinefuse.pubfuse.com"
  );
  assert.equal(
    resolvedGatewayPublicBase({
      headers: { host: "localhost:4000", "x-forwarded-proto": "http" }
    }),
    "http://localhost:4000"
  );
  if (prevG === undefined) {
    delete process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN;
  } else {
    process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN = prevG;
  }
  if (prevA === undefined) {
    delete process.env.CINEFUSE_API_BASE_URL;
  } else {
    process.env.CINEFUSE_API_BASE_URL = prevA;
  }
});

test("projectFilePublicUrl encodes ids", () => {
  const u = projectFilePublicUrl("https://x.com", "p-1", "f 1");
  assert.equal(u, "https://x.com/api/v1/cinefuse/projects/p-1/files/f%201");
});
