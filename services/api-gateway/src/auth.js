export function parseBearerAuth(authorizationHeader) {
  if (!authorizationHeader) {
    return null;
  }

  const [scheme, token] = authorizationHeader.split(" ");
  if (scheme !== "Bearer" || !token) {
    return null;
  }

  // M0 bootstrap auth contract:
  // token format is "user:<userId>"
  if (!token.startsWith("user:")) {
    return null;
  }

  const userId = token.slice(5);
  if (!userId) {
    return null;
  }

  return { userId, token };
}
