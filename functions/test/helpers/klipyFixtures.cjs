/**
 * A recorded KLIPY clips-search response and a fake `fetch` for provider tests.
 *
 * `RECORDED_SEARCH_TEXT` is the body of one real search
 * (`clips/search?q=funny&per_page=8&locale=tr&content_filter=high`, testing key,
 * 2026-10-03), kept as TEXT because that is how the adapter must read it: the
 * third clip's id is larger than 2^53 and `JSON.parse` alone would round it.
 * Redacted: the suffix KLIPY appends to every slug for the calling app, and
 * the base64 `blur_preview` images. Nothing here is, or is derived from, an
 * API key — the key travels in the request URL, which was never recorded.
 *
 * QA / test only. Never imported by a seeder, callable or anything under src/.
 * Not a test file (no `.test.cjs` suffix), so testSuiteCoverage ignores it.
 */

const RECORDED_SEARCH_TEXT = String.raw`{"result":true,"data":{"data":[{"id":3102889768559058,"url":"https:\/\/klipy.com\/clips\/funny-6","title":"Funny.","slug":"funny-6--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/94\/ff\/xJxQxk1o.mp4","gif":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/94\/ff\/2ODNFAoH.gif","webp":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/94\/ff\/WFfPUII8.webp"},"file_meta":{"mp4":{"width":1280,"height":538,"size":101054},"gif":{"width":320,"height":134,"size":164948},"webp":{"width":320,"height":134,"size":16184}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"},
{"id":5998362585366189,"url":"https:\/\/klipy.com\/clips\/right-funny","title":"right, funny","slug":"right-funny--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/897c719aa634cf537cbe94f47c7e4d17\/ef\/53\/lERiCH7y.mp4","gif":"https:\/\/static.klipy.com\/ii\/897c719aa634cf537cbe94f47c7e4d17\/ef\/53\/nF2YTPvT.gif","webp":"https:\/\/static.klipy.com\/ii\/897c719aa634cf537cbe94f47c7e4d17\/ef\/53\/oMMr0l3w.webp"},"file_meta":{"mp4":{"width":624,"height":352,"size":91282},"gif":{"width":320,"height":181,"size":533655},"webp":{"width":320,"height":181,"size":88340}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"},
{"id":9924056256405606,"url":"https:\/\/klipy.com\/clips\/funny-9","title":"Funny.","slug":"funny-9--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/3f\/4d\/jQDu3xeh.mp4","gif":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/3f\/4d\/8Te65Zuu.gif","webp":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/3f\/4d\/HXr9J28u.webp"},"file_meta":{"mp4":{"width":1280,"height":692,"size":153366},"gif":{"width":320,"height":173,"size":460118},"webp":{"width":320,"height":173,"size":76068}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"},
{"id":4589253494475280,"url":"https:\/\/klipy.com\/clips\/funny-like-that","title":"funny like that","slug":"funny-like-that--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/897c719aa634cf537cbe94f47c7e4d17\/cc\/c3\/dKUiwCjO.mp4","gif":"https:\/\/static.klipy.com\/ii\/897c719aa634cf537cbe94f47c7e4d17\/cc\/c3\/QGsnbHcl.gif","webp":"https:\/\/static.klipy.com\/ii\/897c719aa634cf537cbe94f47c7e4d17\/cc\/c3\/OzGh1TeV.webp"},"file_meta":{"mp4":{"width":1280,"height":718,"size":295419},"gif":{"width":320,"height":180,"size":800332},"webp":{"width":320,"height":180,"size":174842}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"},
{"id":2390609995451364,"url":"https:\/\/klipy.com\/clips\/not-funny-thats-not-funny-4","title":"not funny, that's not funny","slug":"not-funny-thats-not-funny-4--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/29\/f8\/J5MH9Xri.mp4","gif":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/29\/f8\/rL3EHDc7.gif","webp":"https:\/\/static.klipy.com\/ii\/48a9760ecdd5307ed701eb96ba85d319\/29\/f8\/JuqVBda7.webp"},"file_meta":{"mp4":{"width":1280,"height":534,"size":139199},"gif":{"width":320,"height":133,"size":440348},"webp":{"width":320,"height":133,"size":52454}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"},
{"id":8689473958651647,"url":"https:\/\/klipy.com\/clips\/funny-EN2","title":"Funny","slug":"funny-EN2--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/fb27cbec3d6194f40b9890e25aad54a3\/cc\/3c\/vr0JvW7h.mp4","gif":"https:\/\/static.klipy.com\/ii\/fb27cbec3d6194f40b9890e25aad54a3\/cc\/3c\/xnTarVlA.gif","webp":"https:\/\/static.klipy.com\/ii\/fb27cbec3d6194f40b9890e25aad54a3\/cc\/3c\/MzlT7KBX.webp"},"file_meta":{"mp4":{"width":1280,"height":536,"size":332474},"gif":{"width":320,"height":134,"size":1020628},"webp":{"width":320,"height":134,"size":170502}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"},
{"id":8251489977663241,"url":"https:\/\/klipy.com\/clips\/you-are-so-funny","title":"You are so funny","slug":"you-are-so-funny--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/d0f4326653a6a0faab99b9987b9a194d\/9f\/57\/7cpI8Vb5.mp4","gif":"https:\/\/static.klipy.com\/ii\/d0f4326653a6a0faab99b9987b9a194d\/9f\/57\/bfqwpBTb.gif","webp":"https:\/\/static.klipy.com\/ii\/d0f4326653a6a0faab99b9987b9a194d\/9f\/57\/8nxxE8et.webp"},"file_meta":{"mp4":{"width":720,"height":408,"size":59012},"gif":{"width":320,"height":181,"size":294401},"webp":{"width":320,"height":181,"size":48898}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"},
{"id":4879181808849718,"url":"https:\/\/klipy.com\/clips\/youre-funny-14","title":"You're funny.","slug":"youre-funny-14--REDACTED","file":{"mp4":"https:\/\/static.klipy.com\/ii\/e85cad6b6c82c51d97e43b629e33eaef\/7f\/3a\/ons7uB6uVKrAfROYvx.mp4","gif":"https:\/\/static.klipy.com\/ii\/e85cad6b6c82c51d97e43b629e33eaef\/7f\/3a\/NIAeftgBsf0s6.gif","webp":"https:\/\/static.klipy.com\/ii\/e85cad6b6c82c51d97e43b629e33eaef\/7f\/3a\/JW6n3UK9IgUlQT.webp"},"file_meta":{"mp4":{"width":894,"height":480,"size":79295},"gif":{"width":320,"height":172,"size":219587},"webp":{"width":320,"height":172,"size":140064}},"tags":[],"type":"clip","blur_preview":"data:image\/jpeg;base64,REDACTED"}],"current_page":1,"per_page":8,"has_next":true,"meta":{"item_min_width":80,"ad_max_resize_percent":10}}}`;

const MEDIA = "https://static.klipy.com/ii/0123456789abcdef0123456789abcdef/aa/bb";

/** A hand-built clip object shaped like the recorded ones. */
function clip({
  id = "1000000000000001",
  title = "Fixture clip",
  type = "clip",
  dir = MEDIA,
  mp4 = {width: 1280, height: 536, size: 200000},
  webp = {width: 320, height: 134, size: 40000},
  gif = {width: 320, height: 134, size: 300000},
  file,
} = {}) {
  return {
    id,
    url: "https://klipy.com/clips/fixture-clip",
    title,
    slug: "fixture-clip--REDACTED",
    file: file ?? {mp4: `${dir}/video.mp4`, gif: `${dir}/preview.gif`, webp: `${dir}/preview.webp`},
    file_meta: {mp4, gif, webp},
    tags: [],
    type,
    blur_preview: "data:image/jpeg;base64,REDACTED",
  };
}

/** A clips-search response body, as text. */
function searchText(clips, {page = 1, hasNext = false} = {}) {
  return JSON.stringify({
    result: true,
    data: {data: clips, current_page: page, per_page: clips.length, has_next: hasNext},
  });
}

/**
 * Fake `fetch` for KlipyHumorSource. Answers `/clips/search` from
 * `textByQuery` (query → response text; `*` is the default) or with
 * `status`. Every requested URL is recorded, so tests can check what was
 * asked — and that nothing else ever sees it.
 */
function fakeKlipyFetch({textByQuery = {"*": RECORDED_SEARCH_TEXT}, status = 200, errorBody = '{"result":false}'} = {}) {
  const calls = [];
  const respond = (code, body) => ({
    ok: code >= 200 && code < 300,
    status: code,
    text: async () => body,
  });
  const fetchImpl = async (url) => {
    const parsed = new URL(url);
    calls.push(parsed);
    if (!parsed.pathname.endsWith("/clips/search")) return respond(404, "{}");
    if (status !== 200) return respond(status, errorBody);
    const q = parsed.searchParams.get("q") ?? "";
    return respond(200, textByQuery[q] ?? textByQuery["*"] ?? searchText([]));
  };
  return {fetchImpl, calls};
}

module.exports = {RECORDED_SEARCH_TEXT, MEDIA, clip, searchText, fakeKlipyFetch};
