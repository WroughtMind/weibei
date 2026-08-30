import assert from "node:assert/strict";
import test from "node:test";
import { isAllowedMainWindowNavigation } from "../src/main/navigation-policy";

test("development navigation stays on the renderer origin", () => {
  const policy = { mode: "development" as const, rendererURL: "http://127.0.0.1:5174/" };

  assert.equal(isAllowedMainWindowNavigation("http://127.0.0.1:5174/settings", policy), true);
  assert.equal(isAllowedMainWindowNavigation("http://127.0.0.1:5174.evil.test/", policy), false);
  assert.equal(isAllowedMainWindowNavigation("http://127.0.0.1:51740/", policy), false);
  assert.equal(isAllowedMainWindowNavigation("https://127.0.0.1:5174/", policy), false);
  assert.equal(isAllowedMainWindowNavigation("file:///tmp/attacker.html", policy), false);
});

test("packaged navigation stays on the loaded renderer file", () => {
  const policy = {
    mode: "packaged" as const,
    rendererEntryURL: "file:///C:/Program%20Files/WeiBei/resources/app.asar/dist/renderer/index.html",
  };

  assert.equal(
    isAllowedMainWindowNavigation(
      "file:///C:/Program%20Files/WeiBei/resources/app.asar/dist/renderer/index.html#settings",
      policy,
    ),
    true,
  );
  assert.equal(
    isAllowedMainWindowNavigation(
      "file:///C:/Program%20Files/WeiBei/resources/app.asar/dist/renderer/other.html",
      policy,
    ),
    false,
  );
  assert.equal(isAllowedMainWindowNavigation("file:///C:/Users/Public/attacker.html", policy), false);
  assert.equal(isAllowedMainWindowNavigation("https://example.com/", policy), false);
  assert.equal(isAllowedMainWindowNavigation("not a URL", policy), false);
});
