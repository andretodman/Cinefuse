import test from "node:test";
import assert from "node:assert/strict";
import { createProject, isValidProjectPhase } from "./index.js";

test("createProject applies defaults", () => {
  const project = createProject({
    id: "proj_1",
    ownerUserId: "user_1",
    title: "Test"
  });

  assert.equal(project.currentPhase, "script");
  assert.equal(project.targetDurationMinutes, 5);
});

test("isValidProjectPhase validates phase", () => {
  assert.equal(isValidProjectPhase("script"), true);
  assert.equal(isValidProjectPhase("invalid"), false);
});
