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

  // M0 bootstrap auth contract:
  // token format is "user:<userId>"
  if (!token.startsWith("user:")) {
    return null;
  }

  const userId = token.slice(5).trim();
  if (!userId) {
    return null;
  }
  // Prevent malformed owner ids that lead to invisible project ownership partitions.
  if (!/^[A-Za-z0-9._@-]{2,128}$/.test(userId)) {
    return null;
  }

  return { userId, token };
}
