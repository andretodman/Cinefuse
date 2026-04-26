const TOOLS = [
  "create_character",
  "train_identity",
  "embed_identity",
  "list_characters",
  "delete_character",
  "preview_character"
];

const characters = new Map();

export function createServer() {
  return {
    name: "character",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }

      if (tool === "create_character") {
        const character = {
          id: input?.id,
          projectId: input?.projectId,
          name: input?.name ?? "Untitled Character",
          description: input?.description ?? "",
          status: "draft",
          previewUrl: null
        };
        characters.set(character.id, character);
        return { ok: true, server: "character", tool, character };
      }

      if (tool === "train_identity") {
        const existing = characters.get(input?.characterId);
        if (!existing) {
          throw new Error("character not found");
        }
        const consistencyScore = 0.87;
        const consistencyThreshold = 0.8;
        const trained = {
          ...existing,
          status: "trained",
          previewUrl: `https://pubfuse.local/cinefuse/characters/${existing.id}/preview.jpg`,
          consistencyScore,
          consistencyThreshold,
          consistencyPassed: consistencyScore >= consistencyThreshold
        };
        characters.set(trained.id, trained);
        return { ok: true, server: "character", tool, character: trained, sparksCost: 500 };
      }

      if (tool === "embed_identity") {
        return {
          ok: true,
          server: "character",
          tool,
          embeddingId: `embed_${input?.characterId ?? "unknown"}`
        };
      }

      if (tool === "list_characters") {
        const projectId = input?.projectId;
        const list = Array.from(characters.values()).filter((item) => item.projectId === projectId);
        return { ok: true, server: "character", tool, characters: list };
      }

      if (tool === "delete_character") {
        characters.delete(input?.characterId);
        return { ok: true, server: "character", tool };
      }

      if (tool === "preview_character") {
        const existing = characters.get(input?.characterId);
        return {
          ok: true,
          server: "character",
          tool,
          previewUrl: existing?.previewUrl ?? `https://pubfuse.local/cinefuse/characters/${input?.characterId ?? "unknown"}/preview.jpg`
        };
      }

      return { ok: true, server: "character", tool, input: input ?? null };
    }
  };
}
