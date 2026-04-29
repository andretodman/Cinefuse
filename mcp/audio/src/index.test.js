import test from "node:test";
import assert from "node:assert/strict";
import { createServer, validateElevenLabsMusicBinaryBody } from "./server.js";

test("audio server exposes tools", () => {
  const server = createServer();
  assert.equal(server.name, "audio");
  assert.equal(server.listTools().includes("mix_scene"), true);
});

test("ElevenLabs music body validator rejects JSON masquerading as audio", () => {
  assert.throws(
    () =>
      validateElevenLabsMusicBinaryBody(Buffer.from('{"detail":[{"msg":"quota"}]}'), "application/json"),
    /elevenlabs_music_response_was_json_not_audio/
  );
});

test("ElevenLabs music body validator accepts typical MP3 buffer", () => {
  const mp3Like = Buffer.alloc(400);
  mp3Like[0] = 0xff;
  mp3Like[1] = 0xfb;
  validateElevenLabsMusicBinaryBody(mp3Like, "audio/mpeg");
});
