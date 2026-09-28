/**
 * Recorded-shape GIPHY API fixtures and a fake `fetch` for provider tests.
 *
 * The objects follow the documented GIF object (id, url, slug, title,
 * username, rating, alt_text, user{...}, images{original, original_mp4,
 * fixed_height, downsized_small, fixed_height_still, original_still}) and the
 * Clips object (video.assets keyed "360p".."4k", video.duration). Values are
 * invented but shaped like real responses — numbers arrive as strings, as
 * GIPHY sends them.
 *
 * QA / test only. Never imported by a seeder, callable or anything under src/.
 * Not a test file (no `.test.cjs` suffix), so testSuiteCoverage ignores it.
 */

const CDN = "https://media1.giphy.com/media";

function renditions(id, {sizes = {}, dims = {}, http = false, host = null} = {}) {
  const base = host ? `https://${host}/media` : http ? "http://media1.giphy.com/media" : CDN;
  const d = {
    original: [480, 270],
    fixed_height: [356, 200],
    downsized_small: [240, 135],
    ...dims,
  };
  const size = (name, fallback) => (name in sizes ? sizes[name] : fallback);
  const strOrUndef = (v) => (v === null || v === undefined ? undefined : String(v));
  return {
    original: {
      url: `${CDN}/${id}/giphy.gif`,
      width: String(d.original[0]),
      height: String(d.original[1]),
      mp4: `${base}/${id}/giphy.mp4`,
      mp4_size: strOrUndef(size("original_mp4", 1_900_000)),
      size: "4800000",
    },
    original_mp4: {
      mp4: `${base}/${id}/giphy.mp4`,
      mp4_size: strOrUndef(size("original_mp4", 1_900_000)),
      width: String(d.original[0]),
      height: String(d.original[1]),
    },
    fixed_height: {
      url: `${CDN}/${id}/200.gif`,
      mp4: `${base}/${id}/200.mp4`,
      mp4_size: strOrUndef(size("fixed_height", 600_000)),
      width: String(d.fixed_height[0]),
      height: String(d.fixed_height[1]),
    },
    downsized_small: {
      mp4: `${base}/${id}/giphy-downsized-small.mp4`,
      mp4_size: strOrUndef(size("downsized_small", 180_000)),
      width: String(d.downsized_small[0]),
      height: String(d.downsized_small[1]),
    },
    fixed_height_still: {
      url: `${CDN}/${id}/200_s.gif`,
      width: String(d.fixed_height[0]),
      height: String(d.fixed_height[1]),
    },
    original_still: {url: `${CDN}/${id}/giphy_s.gif`},
  };
}

/** A GIF object. `user: null` means an anonymous upload. */
function gif({
  id,
  title,
  slug = null,
  username = "",
  displayName = null,
  verified = false,
  rating = "g",
  altText = "",
  isSticker = 0,
  images = null,
  imageOptions = {},
} = {}) {
  const fullSlug = slug ?? `${(title ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${id}`;
  return {
    type: "gif",
    id,
    url: `https://giphy.com/gifs/${fullSlug}`,
    slug: fullSlug,
    title,
    username,
    source_tld: "",
    rating,
    alt_text: altText,
    is_sticker: isSticker,
    user: username
      ? {
          username,
          display_name: displayName ?? username,
          is_verified: verified,
          profile_url: `https://giphy.com/${username}/`,
        }
      : undefined,
    images: images ?? renditions(id, imageOptions),
  };
}

/** A Clips object: GIF-like metadata plus `video.assets`. */
function clip({id, title, username = "", verified = false, rating = "pg", durationSec = 7.5}) {
  const asset = (res, w, h) => ({url: `${CDN}/${id}/${res}.mp4`, width: String(w), height: String(h)});
  return {
    ...gif({id, title, username, verified, rating}),
    type: "video",
    video: {
      duration: durationSec,
      description: `${title} scene`,
      assets: {
        "360p": asset("360p", 640, 360),
        "480p": asset("480p", 854, 480),
        "720p": asset("720p", 1280, 720),
        "1080p": asset("1080p", 1920, 1080),
        "4k": asset("4k", 3840, 2160),
      },
    },
  };
}

/** Named fixtures, one per behaviour the pipeline must get right. */
const FIXTURES = {
  // Accepted: lexicon hits.
  turkishReaction: gif({
    id: "trReact01",
    title: "Komik Tepki GIF by Gain",
    username: "gainmedya",
    displayName: "GAİN",
    verified: true,
    rating: "pg",
    altText: "adam kahkaha atıyor",
  }),
  sitcomReaction: gif({
    id: "sitcom01",
    title: "Sitcom Reaction GIF",
    username: "couchclips",
    rating: "pg-13",
  }),
  laughing: gif({
    id: "laugh01",
    title: "Laughing Out Loud GIF by Comedy Central",
    username: "comedycentral",
    displayName: "Comedy Central",
    verified: false,
  }),
  // Accepted only through verified-account + comedy query (no lexicon word).
  verifiedNoWords: gif({
    id: "office01",
    title: "The Office No GIF by The Office",
    slug: "theoffice-the-office-michael-scott-office01",
    username: "theoffice",
    displayName: "The Office",
    verified: true,
    rating: "pg",
    altText: "Michael Scott yelling no",
  }),
  // Same text, unverified: rejected (no humour marker).
  unverifiedNoWords: gif({
    id: "plain01",
    title: "Man Yelling No GIF",
    username: "someuser",
    altText: "man yelling no",
  }),
  // Generic title, humour only in the slug: accepted, caption null.
  genericTitle: gif({
    id: "generic01",
    title: "GIF",
    slug: "funny-reaction-generic01",
    username: "randomuser",
  }),
  // Title is just the uploader: caption null.
  usernameTitle: gif({
    id: "userttl01",
    title: "couchclips GIF",
    slug: "couchclips-lol-userttl01",
    username: "couchclips",
  }),
  // Rejected: off-topic backdrops and greetings.
  landscape: gif({
    id: "land01",
    title: "Ocean Sunset GIF",
    slug: "nature-ocean-sunset-landscape-land01",
    username: "scenicviews",
    altText: "waves at sunset",
  }),
  funnyWallpaper: gif({
    id: "wall01",
    title: "Funny Wallpaper GIF",
    username: "loops",
  }),
  greeting: gif({
    id: "bday01",
    title: "Happy Birthday Lol GIF by Hallmark",
    username: "hallmark",
    verified: true,
  }),
  turkishGreeting: gif({
    id: "gunay01",
    title: "Günaydın Komik GIF",
    username: "sabahci",
  }),
  abstractLoop: gif({
    id: "abs01",
    title: "Loop Pattern GIF",
    slug: "abstract-loop-pattern-abs01",
    username: "artloops",
  }),
  sticker: gif({
    id: "stk01",
    title: "Laughing Sticker",
    username: "stickerco",
    isSticker: 1,
  }),
  // Rejected: rating.
  ratedR: gif({id: "rated01", title: "Funny Reaction GIF", username: "edgy", rating: "r"}),
  unrated: gif({id: "rated02", title: "Funny Reaction GIF", username: "edgy2", rating: ""}),
  // Rejected: no usable media.
  noMp4: gif({
    id: "nomp401",
    title: "Funny Reaction GIF",
    username: "gifonly",
    images: {
      original: {url: `${CDN}/nomp401/giphy.gif`, width: "480", height: "270"},
      fixed_height_still: {url: `${CDN}/nomp401/200_s.gif`},
    },
  }),
  insecureMedia: gif({
    id: "http01",
    title: "Funny Reaction GIF",
    username: "httpuser",
    imageOptions: {http: true},
  }),
  offHostMedia: gif({
    id: "evil01",
    title: "Funny Reaction GIF",
    username: "eviluser",
    imageOptions: {host: "giphy.com.attacker.tld"},
  }),
  // Within-batch duplicates.
  sitcomReactionRepost: gif({
    id: "sitcom02",
    title: "Sitcom  reaction GIF",
    username: "couchclips",
  }),
  sameMediaDifferentId: {
    ...gif({id: "mirror01", title: "Comedy Scene Lol GIF", username: "mirror"}),
    images: renditions("laugh01"),
  },
};

/** A GIF search response body. */
function searchBody(items, {offset = 0, total = null} = {}) {
  return {
    data: items,
    pagination: {total_count: total ?? items.length + offset, count: items.length, offset},
    meta: {status: 200, msg: "OK", response_id: "fixture"},
  };
}

/**
 * Fake `fetch` for GiphyHumorSource. Routes on the path, answers from
 * `gifsByQuery` (query → GIF objects; `*` is the default), and answers Clips
 * with `clipsStatus` (default 403: no Clips access) or `clipsByQuery`.
 * Every requested URL is recorded, so tests can check what was asked.
 */
function fakeGiphyFetch({gifsByQuery = {}, clipsStatus = 403, clipsByQuery = {}, gifsStatus = 200} = {}) {
  const calls = [];
  const respond = (status, body) => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
  const fetchImpl = async (url) => {
    const parsed = new URL(url);
    calls.push(parsed);
    const q = parsed.searchParams.get("q") ?? "";
    const offset = Number(parsed.searchParams.get("offset") ?? 0);
    if (parsed.pathname.endsWith("/gifs/search")) {
      if (gifsStatus !== 200) return respond(gifsStatus, {meta: {status: gifsStatus}});
      return respond(200, searchBody(gifsByQuery[q] ?? gifsByQuery["*"] ?? [], {offset}));
    }
    if (parsed.pathname.endsWith("/clips/search")) {
      if (clipsStatus !== 200) return respond(clipsStatus, {meta: {status: clipsStatus}});
      return respond(200, searchBody(clipsByQuery[q] ?? clipsByQuery["*"] ?? [], {offset}));
    }
    return respond(404, {});
  };
  return {fetchImpl, calls};
}

module.exports = {FIXTURES, gif, clip, renditions, searchBody, fakeGiphyFetch};
