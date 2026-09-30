#!/usr/bin/env node
/**
 * Measures what a profile photo costs per view before and after the display
 * variants (functions/src/moderation/photoVariants.ts), using the real
 * renderer on the bundled real portraits in assets/images/portraits/.
 *
 * Two inputs per portrait:
 *   as-is    — the 800x1200 JPEG from the repo.
 *   app-1080 — the same photo re-encoded the way the app uploads one
 *              (image_picker maxWidth 1080, imageQuality 85). Upscaled from
 *              800px, so it slightly UNDER-states a real camera photo's size.
 *
 * Then models daily Picks egress with the numbers docs/PICKS_COST_MODEL.md
 * uses (3,000 DAU x 3 opens x 10 cards), before and after.
 *
 *   npm --prefix functions run build && node tool/measureProfilePhotoBytes.cjs
 *
 * Read-only: touches no Firebase project.
 */
const fs = require("node:fs");
const path = require("node:path");

const functionsDir = path.join(__dirname, "..", "functions");
const sharp = require("node:module").createRequire(path.join(functionsDir, "package.json"))("sharp");
const {PHOTO_VARIANTS, renderVariant} = require(path.join(functionsDir, "lib", "moderation", "photoVariants.js"));

const PORTRAITS = path.join(__dirname, "..", "assets", "images", "portraits");
const DAU = 3000;
const OPENS_PER_DAY = 3;
const CARDS_PER_OPEN = 10;

const kb = (n) => `${(n / 1024).toFixed(1)} KB`;
const avg = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

async function main() {
  const rows = [];
  for (const name of fs.readdirSync(PORTRAITS).filter((f) => f.endsWith(".jpg")).sort()) {
    const asIs = fs.readFileSync(path.join(PORTRAITS, name));
    const app1080 = await sharp(asIs).resize({width: 1080}).jpeg({quality: 85}).toBuffer();
    for (const [input, original] of [["as-is", asIs], ["app-1080", app1080]]) {
      const row = {name, input, original: original.length};
      for (const spec of PHOTO_VARIANTS) {
        const out = await renderVariant(original, spec);
        row[spec.name] = out.data.length;
        row[`${spec.name}Px`] = `${out.width}x${out.height}`;
      }
      rows.push(row);
    }
  }

  console.log("portrait      input     original    card (720)          thumb (320)");
  for (const r of rows) {
    console.log(
      `${r.name.padEnd(13)} ${r.input.padEnd(9)} ${kb(r.original).padStart(9)}   ` +
      `${kb(r.card).padStart(9)} ${r.cardPx.padEnd(9)} ${kb(r.thumb).padStart(9)} ${r.thumbPx}`,
    );
  }

  for (const input of ["as-is", "app-1080"]) {
    const set = rows.filter((r) => r.input === input);
    const original = avg(set.map((r) => r.original));
    const card = avg(set.map((r) => r.card));
    const thumb = avg(set.map((r) => r.thumb));
    console.log(`\n[${input}] average per view: original ${kb(original)}, card ${kb(card)} ` +
      `(-${(100 - (card / original) * 100).toFixed(0)}%), thumb ${kb(thumb)} ` +
      `(-${(100 - (thumb / original) * 100).toFixed(0)}%)`);

    const views = DAU * OPENS_PER_DAY * CARDS_PER_OPEN;
    const before = views * original;
    // Picks is a finite daily batch: the same 10 people across the day's
    // opens, so with the disk cache each card image is downloaded once a day.
    const afterDisk = DAU * CARDS_PER_OPEN * original;
    const afterBoth = DAU * CARDS_PER_OPEN * card;
    const gb = (n) => `${(n / 1024 ** 3).toFixed(2)} GB/day`;
    console.log(`  Picks egress, ${DAU} DAU x ${OPENS_PER_DAY} opens x ${CARDS_PER_OPEN} cards:`);
    console.log(`    before (original, every open)        ${gb(before)}`);
    console.log(`    disk cache only (original, once/day)  ${gb(afterDisk)}`);
    console.log(`    disk cache + card variant             ${gb(afterBoth)}  (${(before / afterBoth).toFixed(1)}x less)`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
