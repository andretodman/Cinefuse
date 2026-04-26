import { createHttpServer } from "./http-server.js";

const port = Number(process.env.PORT ?? 4000);

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = createHttpServer();
  server.listen(port, () => {
    console.log(`[api-gateway] listening on http://localhost:${port}`);
  });
}
