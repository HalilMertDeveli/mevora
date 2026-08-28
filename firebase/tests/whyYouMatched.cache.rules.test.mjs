import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rulesPath = path.join(__dirname, '..', 'firestore.rules');
const rules = fs.readFileSync(rulesPath, 'utf8');

assert.match(rules, /function whyYouMatchedCacheDocId\(viewerUid\)/);
assert.match(rules, /function matchMetaReadValid\(matchId, docId\)/);
assert.match(rules, /docId == whyYouMatchedCacheDocId\(request\.auth\.uid\)/);
assert.match(rules, /allow read: if matchMetaReadValid\(matchId, docId\);/);

console.log('whyYouMatched.cache.rules.test.mjs: PASS');
