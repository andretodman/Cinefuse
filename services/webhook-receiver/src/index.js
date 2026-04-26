import { createServer } from "node:http";
import { verifySignature } from "./hmac.js";

const port = Number(process.env.PORT ?? 4010);

function json(response, status, payload) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
}

async function readBody(request) {
  let body = "";
  for await (const chunk of request) {
    body += chunk;
  }
  return body;
}

export function createWebhookServer() {
  return createServer(async (request, response) => {
    const method = request.method ?? "GET";
    const url = new URL(request.url ?? "/", "http://localhost");

    if (method === "GET" && url.pathname === "/health") {
      return json(response, 200, { ok: true, service: "webhook-receiver" });
    }

    if (method === "POST" && url.pathname === "/webhooks/pubfuse") {
      const body = await readBody(request);
      const hmacSecret = process.env.PUBFUSE_HMAC_SECRET ?? "";
      const signatureHeader = request.headers["x-pubfuse-signature"];
      const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;

      const isValid = verifySignature(hmacSecret, body, signature);
      if (!isValid) {
        return json(response, 401, { error: "invalid_signature" });
      }

      return json(response, 200, { ok: true });
    }

    return json(response, 404, { error: "not_found" });
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = createWebhookServer();
  server.listen(port, () => {
    console.log(`[webhook-receiver] listening on http://localhost:${port}`);
  });
}
