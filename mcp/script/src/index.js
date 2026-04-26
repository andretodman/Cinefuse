import { createServer } from "./server.js";

export { createServer };

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = createServer();
  console.log(JSON.stringify({ server: server.name, tools: server.listTools() }, null, 2));
}
