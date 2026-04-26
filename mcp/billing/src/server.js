const TOOLS = [
  "quote_cost",
  "debit",
  "credit",
  "get_balance",
  "redeem_iap_receipt",
  "list_transactions",
  "reconcile_balance"
];

export function createServer(defaultBalance = 100000) {
  return {
    name: "billing",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }

      if (tool === "get_balance") {
        return {
          ok: true,
          server: "billing",
          tool,
          balance: defaultBalance,
          input: input ?? null
        };
      }

      return {
        ok: true,
        server: "billing",
        tool,
        input: input ?? null
      };
    }
  };
}
