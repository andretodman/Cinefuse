export function parseBearerAuth(authorizationHeader) {
  if (!authorizationHeader || typeof authorizationHeader !== "string") {
    return null;
  }
  const match = authorizationHeader.match(/^Bearer\s+(.+)$/);
  if (!match) {
    return null;
  }
  const token = match[1].trim();
  if (!token) {
    return null;
  }

  const userId = resolveUserIdFromToken(token);
  if (!userId) {
    return null;
  }
  // Prevent malformed owner ids that lead to invisible project ownership partitions.
  if (!/^[A-Za-z0-9._@-]{2,128}$/.test(userId)) {
    return null;
  }

  return { userId, token };
}

function resolveUserIdFromToken(token) {
  // M0 bootstrap auth contract:
  // token format is "user:<userId>"
  if (token.startsWith("user:")) {
    return token.slice(5).trim();
  }

  // Remote Pubfuse auth contract:
  // token format is JWT; we decode payload and use a stable subject-like id.
  const jwtUserId = extractJwtUserId(token);
  if (jwtUserId) {
    return jwtUserId;
  }

  return null;
}

function extractJwtUserId(token) {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return null;
  }
  try {
    const payloadRaw = parts[1]
      .replace(/-/g, "+")
      .replace(/_/g, "/");
    const padding = payloadRaw.length % 4 === 0 ? "" : "=".repeat(4 - (payloadRaw.length % 4));
    const payloadJson = Buffer.from(`${payloadRaw}${padding}`, "base64").toString("utf8");
    const payload = JSON.parse(payloadJson);

    const candidate =
      payload?.sub
      ?? payload?.userId
      ?? payload?.user_id
      ?? payload?.id
      ?? payload?.email;

    if (typeof candidate !== "string") {
      return null;
    }
    return candidate.trim();
  } catch {
    return null;
  }
}
