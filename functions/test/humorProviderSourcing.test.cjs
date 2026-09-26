const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {validateHumorSourceItem} = require("../lib/humor/contentValidation.js");

const SRC = path.join(__dirname, "..", "src");

function item(downloadUrl, extra = {}) {
  return {
    sourceId: "abc123",
    type: "video",
    language: "en",
    media: {downloadUrl},
    ...extra,
  };
}

// --------------------------------------------------------------------------
// Secret binding
// --------------------------------------------------------------------------

test("the Giphy secret is bound to the callable that needs it", () => {
  // Declaring a secret with `defineSecret` is not enough — it has to be listed
  // in the function's `secrets` option or it is never mounted at runtime.
  // Without this, `syncHumorFromProvider` answers "not configured" no matter
  // how many times an admin sets the key.
  const source = fs.readFileSync(path.join(SRC, "humor", "index.ts"), "utf8");
  const options = source.slice(
    source.indexOf("export const syncHumorFromProvider"),
    source.indexOf("async (request)", source.indexOf("export const syncHumorFromProvider")),
  );
  assert.ok(options.length > 0, "could not locate syncHumorFromProvider");
  assert.ok(
    /secrets:\s*\[\s*giphyApiKey\s*\]/.test(options),
    `syncHumorFromProvider does not bind giphyApiKey:\n${options}`,
  );
  assert.ok(
    !/secrets:\s*\[\s*\]/.test(options),
    "syncHumorFromProvider still declares an empty secrets array",
  );
});

test("every declared secret is bound to at least one function", () => {
  // The humor secret was the only unbound one in the codebase. Keep it that
  // way: an unbound secret fails silently at runtime, which is the worst kind.
  const declared = new Set();
  const bound = new Set();

  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!entry.name.endsWith(".ts")) continue;
      const text = fs.readFileSync(full, "utf8");
      // Both `export const x = defineSecret(...)` and plain `const x = ...`.
      for (const m of text.matchAll(/(?:export\s+)?const (\w+)\s*=\s*defineSecret\(/g)) {
        declared.add(m[1]);
      }
      for (const m of text.matchAll(/secrets:\s*\[([^\]]*)\]/g)) {
        for (const name of m[1].split(",")) {
          const clean = name.replace(/\.\.\./g, "").trim();
          if (clean) bound.add(clean);
        }
      }
      // Grouped exports such as `export const diditSecrets = [a, b]`.
      for (const m of text.matchAll(/export const \w*[Ss]ecrets\s*=\s*\[([^\]]*)\]/g)) {
        for (const name of m[1].split(",")) {
          const clean = name.trim();
          if (clean) bound.add(clean);
        }
      }
    }
  };
  walk(SRC);

  // Guard against the scanner silently matching nothing, without pinning a
  // count that every new secret would have to chase.
  assert.ok(
    declared.has("giphyApiKey"),
    `scanner failed — found: ${[...declared].sort().join(", ")}`,
  );

  const unbound = [...declared].filter((name) => !bound.has(name)).sort();
  assert.deepEqual(
    unbound,
    [],
    `declared but never mounted into a function: ${unbound.join(", ")}`,
  );
});

// --------------------------------------------------------------------------
// Media host allowlist
// --------------------------------------------------------------------------

test("real Giphy CDN shards are accepted", () => {
  for (const host of [
    "media.giphy.com",
    "media0.giphy.com",
    "media4.giphy.com",
    "i.giphy.com",
    "giphy.com",
  ]) {
    const result = validateHumorSourceItem(item(`https://${host}/media/x/giphy.mp4`));
    assert.equal(result.ok, true, `${host} rejected: ${result.reason}`);
  }
});

test("a lookalike host cannot impersonate an allowed one", () => {
  // The old substring match accepted every one of these.
  for (const host of [
    "giphy.com.attacker.tld",
    "notgiphy.com",
    "evil-picsum.photos.cdn.tld",
    "picsum.photos.attacker.tld",
    "firebasestorage.googleapis.com.evil.tld",
    "mygiphy.com",
  ]) {
    const result = validateHumorSourceItem(item(`https://${host}/x.mp4`));
    assert.equal(result.ok, false, `${host} was accepted`);
    assert.equal(result.reason, "host-not-allowed");
  }
});

test("a giphy sourceUrl cannot vouch for media on another host", () => {
  // Both fields come from the same provider payload, so one must not be
  // allowed to authorise the other.
  const result = validateHumorSourceItem(
    item("https://attacker.tld/payload.mp4", {
      sourceUrl: "https://giphy.com/gifs/abc123",
    }),
  );
  assert.equal(result.ok, false, "the sourceUrl escape hatch is still open");
  assert.equal(result.reason, "host-not-allowed");
});

test("plain http is refused even on an allowed host", () => {
  const result = validateHumorSourceItem(item("http://media.giphy.com/x.mp4"));
  assert.equal(result.ok, false);
  assert.equal(result.reason, "insecure-url");
});

test("missing or malformed input is refused before host checks", () => {
  assert.equal(
    validateHumorSourceItem({sourceId: "", type: "video", language: "en", media: {}})
      .reason,
    "missing-sourceId",
  );
  assert.equal(
    validateHumorSourceItem({
      sourceId: "a",
      type: "video",
      language: "en",
      media: {},
    }).reason,
    "missing-media-url",
  );
  assert.equal(validateHumorSourceItem(item("not-a-url")).reason, "invalid-url");
});

test("the internal seed hosts still validate", () => {
  // Whatever the allowlist does, it must not lock out our own curated media.
  const {CALIBRATION_SEED} = require("../lib/humor/calibrationSeed.js");
  for (const seed of CALIBRATION_SEED) {
    for (const url of [seed.media.downloadUrl, seed.media.thumbUrl]) {
      const result = validateHumorSourceItem(item(url));
      assert.equal(result.ok, true, `${seed.contentId} ${url}: ${result.reason}`);
    }
  }
});
