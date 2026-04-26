import test from "node:test";
import assert from "node:assert/strict";
import { PROJECT_PHASES } from "./index.js";

test("project phases include M0 pipeline start", () => {
  assert.equal(PROJECT_PHASES.includes("script"), true);
  assert.equal(PROJECT_PHASES.includes("export"), true);
});
