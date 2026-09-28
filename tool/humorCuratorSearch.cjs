#!/usr/bin/env node
/**
 * Harvests curated-catalogue candidates from GIPHY through a running
 * Functions EMULATOR, for a human to review and pick from.
 *
 * It calls the admin-only, emulator-only `searchHumorProviderCandidates`
 * callable once per (dimension, language) group of a query plan
 * (tool/humorCuratorQueryPlan.json by default), as a throwaway admin it
 * creates in the Auth emulator and deletes at the end. The callable writes
 * nothing; this script writes nothing to any emulator either — only:
 *   --out <file.json>   every candidate, merged by GIPHY id, with the
 *                       dimensions / queries that found it;
 *   --stills <dir>      each candidate's still (small GIF, GIPHY CDN only) as
 *                       <giphyId>.gif, plus review.html (a contact sheet;
 *                       hovering a still loads the animated WebP).
 *
 * The GIPHY key stays inside the Functions emulator process. This script
 * never reads, receives or prints it: the callable returns media URLs only.
 *
 * Usage (repo root, emulator suite already running with the key loaded):
 *
 *   node tool/humorCuratorSearch.cjs --out .tmp/humor-curation/candidates.json \
 *     --stills .tmp/humor-curation/stills \
 *     [--functions-host 127.0.0.1:5001] [--auth-host 127.0.0.1:9099] \
 *     [--project mevora-d6ed0] [--plan tool/humorCuratorQueryPlan.json] \
 *     [--dimensions sarcasm,dry] [--per-query 25] [--offset 0] [--rating pg-13]
 *
 *   node tool/humorCuratorSearch.cjs --print-plan     # show the plan, call nothing
 *
 * Exit codes: 0 ok · 2 bad usage / refused · 3 the emulator has no GIPHY key ·
 * 1 anything else.
 */
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {createRequire} = require("node:module");

const REPO_ROOT = path.join(__dirname, "..");
const FUNCTIONS_DIR = path.join(REPO_ROOT, "functions");
const DEFAULT_PLAN = path.join(__dirname, "humorCuratorQueryPlan.json");

const LOOPBACK_HOST = /^(?:127(?:\.\d{1,3}){3}|localhost|\[::1\]):\d{1,5}$/i;
const DIMENSIONS = [
  "sarcasm", "absurd", "silly", "romantic", "dark", "meme", "dry", "wordplay",
  "situational", "cringe", "teasing",
];
const RATINGS = ["g", "pg", "pg-13"];
const MAX_QUERIES_PER_CALL = 12;
const MAX_STILL_BYTES = 2_000_000;
const GIPHY_ID = /^[A-Za-z0-9]{4,64}$/;

// --------------------------------------------------------------------------
// Pure helpers (exported for tests)
// --------------------------------------------------------------------------

function parseArgs(argv) {
  const value = (name) => {
    const index = argv.indexOf(name);
    return index >= 0 ? argv[index + 1] : undefined;
  };
  const int = (name, fallback) => {
    const raw = value(name);
    if (raw === undefined) return fallback;
    const n = Number(raw);
    return Number.isInteger(n) ? n : NaN;
  };
  return {
    out: value("--out"),
    stills: value("--stills"),
    functionsHost: value("--functions-host") ?? "127.0.0.1:5001",
    authHost: value("--auth-host") ?? "127.0.0.1:9099",
    project: value("--project") ?? (process.env.QA_PROJECT_ID || "mevora-d6ed0"),
    plan: value("--plan") ?? DEFAULT_PLAN,
    dimensions: value("--dimensions")
      ? value("--dimensions").split(",").map((d) => d.trim()).filter(Boolean)
      : null,
    perQuery: int("--per-query", null),
    offset: int("--offset", 0),
    rating: value("--rating") ?? null,
    printPlan: argv.includes("--print-plan"),
  };
}

/** Problems with the arguments; empty when usable. */
function argProblems(args) {
  const problems = [];
  if (!args.printPlan && !args.out) problems.push("--out <file.json> is required");
  for (const [flag, host] of [["--functions-host", args.functionsHost], ["--auth-host", args.authHost]]) {
    if (!LOOPBACK_HOST.test(host ?? "")) problems.push(`${flag} must be a loopback host:port`);
  }
  if (!/^[a-z0-9][a-z0-9-]{2,62}$/.test(args.project ?? "")) problems.push("--project is invalid");
  if (args.perQuery !== null && !(args.perQuery >= 1 && args.perQuery <= 50)) {
    problems.push("--per-query must be 1..50");
  }
  if (!(args.offset >= 0 && args.offset <= 4999)) problems.push("--offset must be 0..4999");
  if (args.rating !== null && !RATINGS.includes(args.rating)) {
    problems.push(`--rating must be one of ${RATINGS.join(", ")}`);
  }
  for (const d of args.dimensions ?? []) {
    if (!DIMENSIONS.includes(d)) problems.push(`unknown dimension ${d}`);
  }
  return problems;
}

/** Problems with a query plan; empty when usable. */
function planProblems(plan) {
  const problems = [];
  if (!plan || !Array.isArray(plan.groups) || plan.groups.length === 0) {
    return ["plan.groups must be a non-empty array"];
  }
  if (plan.rating !== undefined && !RATINGS.includes(plan.rating)) problems.push("plan.rating");
  plan.groups.forEach((group, i) => {
    const where = `groups[${i}]`;
    if (!DIMENSIONS.includes(group.dimension)) problems.push(`${where}.dimension`);
    if (group.lang !== "tr" && group.lang !== "en") problems.push(`${where}.lang`);
    if (!Array.isArray(group.queries) || group.queries.length === 0 ||
        group.queries.length > MAX_QUERIES_PER_CALL) {
      problems.push(`${where}.queries`);
      return;
    }
    for (const q of group.queries) {
      if (typeof q !== "string" || !q.trim() || q.trim().length > 50) {
        problems.push(`${where}.queries: "${q}"`);
      }
    }
  });
  return problems;
}

/** The still to download for a candidate: GIPHY CDN over https only. */
function stillUrlOf(candidate) {
  for (const raw of [candidate?.media?.stillUrl, candidate?.media?.stableStillUrl]) {
    if (typeof raw !== "string") continue;
    try {
      const url = new URL(raw);
      const host = url.hostname.toLowerCase();
      if (url.protocol === "https:" && (host === "giphy.com" || host.endsWith(".giphy.com"))) {
        return url.toString();
      }
    } catch (_) {
      // try the next one
    }
  }
  return null;
}

/**
 * Merges one callable result into `byId` (GIPHY id → candidate). A candidate
 * found by several groups keeps its first record and gains every
 * {dimension, lang, queries} that found it.
 */
function mergeCandidates(byId, group, result) {
  for (const candidate of result.candidates ?? []) {
    if (!candidate || !GIPHY_ID.test(candidate.giphyId ?? "")) continue;
    const hit = {dimension: group.dimension, lang: group.lang, queries: candidate.queries ?? [], rank: candidate.rank};
    const existing = byId.get(candidate.giphyId);
    if (existing) {
      existing.foundBy.push(hit);
    } else {
      const {queries: _q, rank: _r, ...rest} = candidate;
      byId.set(candidate.giphyId, {...rest, foundBy: [hit]});
    }
  }
  return byId;
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[ch]);
}

/** A static contact sheet: one section per dimension, stills from disk. */
function reviewHtml(candidates) {
  const sections = DIMENSIONS.map((dimension) => {
    const items = candidates.filter((c) => c.foundBy.some((f) => f.dimension === dimension));
    if (items.length === 0) return "";
    const cards = items.map((c) => {
      const webp = c.media?.rendition?.url ?? c.media?.stableWebpUrl ?? "";
      const size = c.media?.rendition?.sizeBytes;
      const verdict = c.relevance?.ok ? `ok (${c.relevance.basis})` : `rejected: ${c.relevance?.reason}`;
      const queries = c.foundBy.filter((f) => f.dimension === dimension)
        .map((f) => `${f.lang}: ${f.queries.join(" / ")}`).join("; ");
      return `<figure class="${c.relevance?.ok ? "ok" : "no"}">
  <img src="${escapeHtml(c.stillFile ?? "")}" data-still="${escapeHtml(c.stillFile ?? "")}" data-anim="${escapeHtml(webp)}" loading="lazy" alt="">
  <figcaption><b>${escapeHtml(c.giphyId)}</b> ${escapeHtml(c.title ?? "(no caption)")}<br>
  @${escapeHtml(c.username ?? "?")}${c.verified ? " ✔" : ""} · ${escapeHtml(c.rating ?? "?")} · ${escapeHtml(c.providerTrust)}<br>
  ${escapeHtml(c.media?.rendition?.name ?? "no rendition")} ${size ? `${Math.round(size / 1024)} KB` : ""} · ${escapeHtml(verdict)}<br>
  <small>${escapeHtml(queries)}</small> · <a href="${escapeHtml(c.sourceUrl ?? "#")}" target="_blank" rel="noopener">GIPHY</a></figcaption>
</figure>`;
    }).join("\n");
    return `<h2>${dimension} (${items.length})</h2>\n<div class="grid">\n${cards}\n</div>`;
  }).join("\n");
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Humor curation candidates</title>
<style>
body{font:13px system-ui,sans-serif;margin:16px;background:#fafafa;color:#222}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}
figure{margin:0;background:#fff;border:1px solid #ddd;border-radius:6px;padding:6px}
figure.no{opacity:.55}
img{width:100%;height:160px;object-fit:contain;background:#eee}
</style></head><body>
<h1>Humor curation candidates</h1>
<p>Hover a still to play the animated rendition (loads from GIPHY). Faded cards failed the ordinary relevance filter (advisory).</p>
${sections}
<script>
document.querySelectorAll("img[data-anim]").forEach(function (img) {
  img.addEventListener("mouseenter", function () { if (img.dataset.anim) img.src = img.dataset.anim; });
  img.addEventListener("mouseleave", function () { img.src = img.dataset.still; });
});
</script>
</body></html>
`;
}

// --------------------------------------------------------------------------
// Side effects
// --------------------------------------------------------------------------

async function postJson(url, body, headers = {}, timeoutMs = 120000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {"Content-Type": "application/json", ...headers},
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const json = await response.json().catch(() => ({}));
    return {status: response.status, json};
  } finally {
    clearTimeout(timer);
  }
}

async function downloadStill(url, file) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const response = await fetch(url, {signal: controller.signal});
    if (!response.ok) return `HTTP ${response.status}`;
    // A redirect must not take us off GIPHY's CDN.
    if (response.url && !stillUrlOf({media: {stillUrl: response.url}})) return "redirected off GIPHY";
    const type = response.headers.get("content-type") ?? "";
    if (!type.startsWith("image/")) return `not an image (${type})`;
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > MAX_STILL_BYTES) return "too large";
    fs.writeFileSync(file, bytes);
    return null;
  } catch (error) {
    return error && error.name === "AbortError" ? "timeout" : "network error";
  } finally {
    clearTimeout(timer);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const problems = argProblems(args);
  let plan;
  try {
    plan = JSON.parse(fs.readFileSync(path.resolve(args.plan), "utf8"));
  } catch (error) {
    problems.push(`cannot read plan ${args.plan}: ${error.message}`);
  }
  if (plan) problems.push(...planProblems(plan));
  if (problems.length > 0) {
    console.error(`REFUSING TO RUN:\n  - ${problems.join("\n  - ")}`);
    return 2;
  }
  const groups = plan.groups.filter((g) => !args.dimensions || args.dimensions.includes(g.dimension));
  const perQuery = args.perQuery ?? plan.perQuery ?? 25;
  const rating = args.rating ?? plan.rating ?? "pg-13";

  if (args.printPlan) {
    for (const g of groups) console.log(`${g.dimension.padEnd(12)} ${g.lang}  ${g.queries.join(" | ")}`);
    console.log(`${groups.length} groups · perQuery ${perQuery} · rating ${rating} · offset ${args.offset}`);
    return 0;
  }

  // Auth emulator only: with this set, the Admin SDK cannot reach real Auth.
  process.env.FIREBASE_AUTH_EMULATOR_HOST = args.authHost;
  const fromFunctions = createRequire(path.join(FUNCTIONS_DIR, "package.json"));
  let admin;
  try {
    admin = fromFunctions("firebase-admin");
  } catch (_) {
    console.error("firebase-admin not found — run: npm --prefix functions ci");
    return 2;
  }
  admin.initializeApp({projectId: args.project}, `humor-curator-${Date.now()}`);
  const app = admin.apps[admin.apps.length - 1];

  const email = `humor-curator-${crypto.randomBytes(6).toString("hex")}@mevora.test`;
  // Emulator-only credential for a user deleted at the end; never printed.
  const password = crypto.randomBytes(24).toString("base64url");
  let uid = null;
  const byId = new Map();
  const report = [];
  let exitCode = 0;
  try {
    const user = await app.auth().createUser({email, password, displayName: "Humor curator (emulator)"});
    uid = user.uid;
    await app.auth().setCustomUserClaims(uid, {admin: true});
    const signIn = await postJson(
      `http://${args.authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator`,
      {email, password, returnSecureToken: true},
    );
    const idToken = signIn.json && signIn.json.idToken;
    if (!idToken) {
      console.error(`emulator sign-in failed: HTTP ${signIn.status}`);
      return 1;
    }

    const endpoint = `http://${args.functionsHost}/${args.project}/europe-west1/searchHumorProviderCandidates`;
    console.log(`Harvesting ${groups.length} groups via ${args.functionsHost} (project ${args.project})`);
    for (const group of groups) {
      const call = await postJson(
        endpoint,
        {data: {queries: group.queries, perQuery, lang: group.lang, offset: args.offset, rating, dimension: group.dimension}},
        {Authorization: `Bearer ${idToken}`},
      );
      const result = call.json && call.json.result;
      if (!result) {
        const error = call.json && call.json.error;
        console.error(
          `  ${group.dimension}/${group.lang}: HTTP ${call.status}` +
            `${error ? ` ${error.status ?? ""} ${error.message ?? ""}` : ""}`,
        );
        if (call.status === 404) {
          console.error("  (the emulator does not serve searchHumorProviderCandidates — is this branch's code running there?)");
          return 1;
        }
        exitCode = 1;
        continue;
      }
      if (result.configured === false) {
        console.error("The Functions emulator has no GIPHY key loaded (functions/.secret.local in the worktree it serves).");
        return 3;
      }
      mergeCandidates(byId, group, result);
      const errors = (result.queries ?? []).filter((q) => q.error).map((q) => `${q.query}: ${q.error}`);
      report.push({dimension: group.dimension, lang: group.lang, queries: result.queries, counts: result.counts});
      console.log(
        `  ${group.dimension.padEnd(12)} ${group.lang}  received ${result.counts.received}, ` +
          `unique ${result.counts.unique}, relevant ${result.counts.relevant}` +
          `${errors.length ? `  errors: ${errors.join("; ")}` : ""}`,
      );
    }
  } finally {
    if (uid) await app.auth().deleteUser(uid).catch(() => {});
    await app.delete().catch(() => {});
  }

  const candidates = [...byId.values()];
  if (args.stills) {
    const dir = path.resolve(args.stills);
    fs.mkdirSync(dir, {recursive: true});
    let saved = 0;
    const failures = {};
    const queue = [...candidates];
    const worker = async () => {
      while (queue.length > 0) {
        const candidate = queue.shift();
        const url = stillUrlOf(candidate);
        if (!url) {
          failures["no still"] = (failures["no still"] ?? 0) + 1;
          continue;
        }
        const file = path.join(dir, `${candidate.giphyId}.gif`);
        const problem = fs.existsSync(file) ? null : await downloadStill(url, file);
        if (problem) {
          failures[problem] = (failures[problem] ?? 0) + 1;
        } else {
          candidate.stillFile = `${candidate.giphyId}.gif`;
          saved += 1;
        }
      }
    };
    await Promise.all(Array.from({length: 6}, worker));
    fs.writeFileSync(path.join(dir, "review.html"), reviewHtml(candidates));
    const failed = Object.entries(failures).map(([k, n]) => `${k} ${n}`).join(", ");
    console.log(`  stills: ${saved}/${candidates.length} in ${dir}${failed ? ` (failed: ${failed})` : ""}`);
    console.log(`  contact sheet: ${path.join(dir, "review.html")}`);
  }

  const out = path.resolve(args.out);
  fs.mkdirSync(path.dirname(out), {recursive: true});
  fs.writeFileSync(
    out,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        functionsHost: args.functionsHost,
        project: args.project,
        perQuery,
        offset: args.offset,
        rating,
        groups: report,
        candidates,
      },
      null,
      2,
    ),
  );
  console.log(`  ${candidates.length} unique candidates → ${out}`);
  return exitCode;
}

if (require.main === module) {
  main().then(
    (code) => {
      process.exitCode = code;
      setTimeout(() => process.exit(code), 250).unref();
    },
    (error) => {
      console.error("HUMOR CURATOR SEARCH FAILED:", error && error.message ? error.message : error);
      process.exitCode = 1;
      setTimeout(() => process.exit(1), 250).unref();
    },
  );
}

module.exports = {
  DIMENSIONS,
  argProblems,
  mergeCandidates,
  parseArgs,
  planProblems,
  reviewHtml,
  stillUrlOf,
};
