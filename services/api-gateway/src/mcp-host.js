import { createServer as createPubfuseServer } from "../../../mcp/pubfuse/src/server.js";
import { createServer as createBillingServer } from "../../../mcp/billing/src/server.js";
import { createServer as createScriptServer } from "../../../mcp/script/src/server.js";
import { createServer as createCharacterServer } from "../../../mcp/character/src/server.js";
import { createServer as createClipServer } from "../../../mcp/clip/src/server.js";
import { createServer as createAudioServer } from "../../../mcp/audio/src/server.js";
import { createServer as createStitchServer } from "../../../mcp/stitch/src/server.js";
import { createServer as createExportServer } from "../../../mcp/export/src/server.js";

export function createMcpHost() {
  const servers = new Map([
    ["pubfuse", createPubfuseServer()],
    ["billing", createBillingServer()],
    ["script", createScriptServer()],
    ["character", createCharacterServer()],
    ["clip", createClipServer()],
    ["audio", createAudioServer()],
    ["stitch", createStitchServer()],
    ["export", createExportServer()]
  ]);

  return {
    listServers() {
      return Array.from(servers.keys());
    },
    listTools(serverName) {
      const server = servers.get(serverName);
      if (!server) {
        throw new Error(`Unknown MCP server: ${serverName}`);
      }
      return server.listTools();
    },
    invoke(serverName, tool, input) {
      const server = servers.get(serverName);
      if (!server) {
        throw new Error(`Unknown MCP server: ${serverName}`);
      }
      return server.invoke(tool, input);
    }
  };
}
