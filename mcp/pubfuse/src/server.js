const TOOLS = [
  "get_user",
  "update_profile",
  "list_files",
  "upload_file",
  "get_file_url",
  "create_scheduled_event",
  "get_spark_balance",
  "verify_webhook_hmac"
];

export function createServer() {
  return {
    name: "pubfuse",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }
      return {
        ok: true,
        server: "pubfuse",
        tool,
        input: input ?? null
      };
    }
  };
}
