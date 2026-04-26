function buildHeaders(config, extra = {}) {
  return {
    "content-type": "application/json",
    "x-pubfuse-app-id": config.appId,
    authorization: `Bearer ${config.clientSecret}`,
    ...extra
  };
}

export function createPubfuseClient(config) {
  return {
    async getUser(userId) {
      const response = await fetch(`${config.baseUrl}/api/users/${userId}`, {
        method: "GET",
        headers: buildHeaders(config, { "x-client-id": config.clientId })
      });
      return response.json();
    },
    async getBalance(userId) {
      const response = await fetch(`${config.baseUrl}/api/sparks/balance/${userId}`, {
        method: "GET",
        headers: buildHeaders(config, { "x-client-id": config.clientId })
      });
      return response.json();
    }
  };
}
