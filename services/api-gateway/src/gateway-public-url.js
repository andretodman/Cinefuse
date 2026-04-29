/**
 * Public base URL helpers for file URLs (sound ingest, uploads).
 * Kept in a small module so contract/unit tests can assert behavior without booting the full HTTP server.
 */

/** No trailing slash. Env only (used when building outbound upload URLs without an HTTP request). */
export function gatewayPublicOriginFromEnv() {
  return (
    (process.env.CINEFUSE_GATEWAY_PUBLIC_ORIGIN ?? process.env.CINEFUSE_API_BASE_URL ?? "")
      .trim()
      .replace(/\/+$/, "")
  );
}

/**
 * Public base URL for file URLs in JSON responses. Uses env first, then `Host` / `X-Forwarded-*`
 * so internal ingest works when `CINEFUSE_GATEWAY_PUBLIC_ORIGIN` is unset behind a reverse proxy.
 * @param {import("node:http").IncomingMessage | { headers?: Record<string, string | string[] | undefined> }} request
 */
export function resolvedGatewayPublicBase(request) {
  const fromEnv = gatewayPublicOriginFromEnv();
  if (fromEnv.length > 0) {
    return fromEnv;
  }
  if (!request?.headers) {
    return "";
  }
  const host = String(request.headers["x-forwarded-host"] ?? request.headers.host ?? "")
    .split(",")[0]
    .trim();
  if (!host) {
    return "";
  }
  const protoRaw = String(request.headers["x-forwarded-proto"] ?? "")
    .split(",")[0]
    .trim()
    .toLowerCase();
  const scheme = protoRaw === "https" || protoRaw === "http" ? protoRaw : "https";
  return `${scheme}://${host}`.replace(/\/+$/, "");
}

export function projectFilePublicUrl(base, projectId, fileId) {
  if (!base || !projectId || !fileId) {
    return null;
  }
  return `${base}/api/v1/cinefuse/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(fileId)}`;
}
