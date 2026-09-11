const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildMovieStreams,
  chooseVideo,
  createLookupCache,
  createRequestGate,
  handleRequest,
  manifest,
  parseJsonResponse,
} = require("./app");

test("manifest exposes movie streams for IMDb IDs", () => {
  assert.equal(manifest.id, "xyz.dimensiondoor.internet-archive");
  assert.deepEqual(manifest.resources, ["stream"]);
  assert.deepEqual(manifest.types, ["movie"]);
  assert.deepEqual(manifest.idPrefixes, ["tt"]);
});

test("buildMovieStreams returns one complete original video per Archive item", async () => {
  const calls = [];
  const fetchJson = async (url) => {
    calls.push(url);
    if (url.includes("v3-cinemeta")) {
      return {
        meta: {
          name: "La Commune (Paris, 1871)",
          runtime: "346 min",
          year: "2000",
        },
      };
    }
    if (url.includes("advancedsearch")) {
      return {
        response: {
          docs: [
            {},
            {
              identifier: "missing-archive-item",
              title: "La Commune (Paris, 1871)",
              year: 2000,
            },
            {
              identifier: "null-title-item",
              title: null,
              year: 2000,
            },
            {
              identifier: "discussion-about-la-commune",
              title: "Discussion of La Commune (Paris, 1871)",
              year: 2000,
            },
            {
              identifier: "historical-fiction",
              title: "La Commune (Paris, 1871s)",
              year: 2000,
            },
            {
              identifier: "la-commune-paris-1871-eng-sub",
              title: "La Commune (Paris, 1871) ENG SUB",
              year: 2000,
            },
            {
              identifier: "unrelated-2021-video",
              title: "La Commune de Paris - 1871",
              year: 2021,
            },
          ],
        },
      };
    }
    if (url.includes("/metadata/missing-archive-item")) {
      throw new Error("Archive item unavailable");
    }
    if (url.includes("/metadata/la-commune-paris-1871-eng-sub")) {
      return {
        files: [
          null,
          { name: null, length: "20760" },
          {
            name: "trailer.mp4",
            format: "MPEG4",
            length: "120",
            size: "1000",
            source: "original",
          },
          {
            name: "La Commune (Paris, 1871) ENG SUB.mp4",
            format: "MPEG4",
            height: "360",
            length: "20760",
            size: "1611778407",
            source: "original",
          },
          {
            name: "La Commune (Paris, 1871) ENG SUB.ia.mp4",
            format: "h.264",
            height: "360",
            length: "20760",
            size: "800000000",
            source: "derivative",
          },
          {
            name: "La Commune (Paris, 1871) EXTENDED.mp4",
            format: "MPEG4",
            height: "1080",
            length: "50000",
            size: "3000000000",
            source: "original",
          },
          {
            name: "La Commune (Paris, 1871) ENG SUB.srt",
            format: "SubRip",
          },
          {
            name: "other-cut.srt",
            format: "SubRip",
          },
        ],
      };
    }
    throw new Error(`Unexpected URL: ${url}`);
  };

  const result = await buildMovieStreams("tt0257497", fetchJson);

  assert.equal(result.streams.length, 1);
  assert.equal(
    result.streams[0].url,
    "https://archive.org/download/la-commune-paris-1871-eng-sub/La%20Commune%20(Paris%2C%201871)%20ENG%20SUB.mp4",
  );
  assert.equal(result.streams[0].behaviorHints.notWebReady, false);
  assert.equal(result.streams[0].behaviorHints.videoSize, 1611778407);
  assert.deepEqual(result.streams[0].subtitles, [
    {
      id: "La Commune (Paris, 1871) ENG SUB.srt",
      lang: "eng",
      url: "https://archive.org/download/la-commune-paris-1871-eng-sub/La%20Commune%20(Paris%2C%201871)%20ENG%20SUB.srt",
    },
  ]);
  assert.match(calls[1], /advancedsearch\.php/);
  assert.equal(calls.some((url) => url.includes("discussion-about-la-commune")), false);
  assert.equal(calls.some((url) => url.includes("historical-fiction")), false);
});

test("buildMovieStreams does not treat total item failure as a stable empty result", async () => {
  let request = 0;
  await assert.rejects(
    buildMovieStreams("tt0257497", async () => {
      request += 1;
      if (request === 1) {
        return { meta: { name: "La Commune (Paris, 1871)", runtime: "345 min", year: 2000 } };
      }
      if (request === 2) {
        return {
          response: {
            docs: [
              {
                identifier: "temporary-failure",
                title: "La Commune (Paris, 1871)",
                year: 2000,
              },
            ],
          },
        };
      }
      throw new Error("Archive unavailable");
    }),
    /Archive item lookup failed/,
  );
});

test("chooseVideo prefers a playable MP4 over an original AVI", () => {
  const selected = chooseVideo(
    [
      { name: "movie.avi", length: "6000", source: "original", height: "720" },
      { name: "movie.mp4", length: "6000", source: "derivative", height: "480" },
    ],
    5000,
    7000,
  );

  assert.equal(selected.name, "movie.mp4");
});

test("buildMovieStreams rejects malformed IMDb IDs without an upstream request", async () => {
  let called = false;
  const result = await buildMovieStreams("../../secrets", async () => {
    called = true;
    return {};
  });

  assert.deepEqual(result, { streams: [] });
  assert.equal(called, false);
});

test("lookup cache deduplicates requests and evicts old entries at its limits", async () => {
  const lookupCache = createLookupCache({
    maxEntries: 2,
    maxBytes: 40,
    ttlMs: 60_000,
    maxActive: 2,
  });
  let calls = 0;
  let release;
  const pending = new Promise((resolve) => {
    release = resolve;
  });
  const loader = async () => {
    calls += 1;
    await pending;
    return { streams: [] };
  };

  const first = lookupCache.get("tt1", loader);
  const duplicate = lookupCache.get("tt1", loader);
  release();
  await Promise.all([first, duplicate]);
  await lookupCache.get("tt2", async () => ({ streams: [] }));
  await lookupCache.get("tt3", async () => ({ streams: [] }));
  let cacheMiss = false;
  await lookupCache.get("tt2", async () => {
    cacheMiss = true;
    return { streams: [] };
  });

  assert.equal(calls, 1);
  assert.equal(cacheMiss, false);
  assert.equal(lookupCache.size(), 2);
  assert.equal(lookupCache.bytes() <= 40, true);
});

test("lookup cache rejects excess distinct active requests", async () => {
  const lookupCache = createLookupCache({
    maxEntries: 2,
    maxBytes: 100,
    ttlMs: 60_000,
    maxActive: 1,
  });
  let release;
  const pending = new Promise((resolve) => {
    release = resolve;
  });

  const first = lookupCache.get("tt1", () => pending);
  await assert.rejects(
    lookupCache.get("tt2", async () => ({ streams: [] })),
    /busy/,
  );
  release({ streams: [] });
  await first;
});

test("request gate caps waiters even when they share one lookup", async () => {
  const gate = createRequestGate(1);
  let release;
  const pending = new Promise((resolve) => {
    release = resolve;
  });
  const first = gate.run(() => pending);
  await assert.rejects(gate.run(() => pending), /Too many active stream requests/);
  release({ streams: [] });
  await first;
  assert.equal(gate.active(), 0);
});

test("JSON parser rejects an upstream body above its byte limit", async () => {
  const response = new Response(JSON.stringify({ value: "x".repeat(100) }));
  await assert.rejects(parseJsonResponse(response, 32), /too large/);
});

test("HTTP handler answers CORS preflight requests", async () => {
  const request = { method: "OPTIONS", url: "/manifest.json" };
  const result = { status: null, headers: null, body: null };
  const response = {
    writeHead(status, headers) {
      result.status = status;
      result.headers = headers;
    },
    end(body = "") {
      result.body = body;
    },
  };

  await handleRequest(request, response);

  assert.equal(result.status, 204);
  assert.equal(result.headers["access-control-allow-origin"], "*");
  assert.equal(result.headers["access-control-allow-methods"], "GET, OPTIONS");
  assert.equal(result.body, "");
});
