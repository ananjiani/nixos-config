"use strict";

const http = require("node:http");

const PORT = Number.parseInt(process.env.PORT || "7000", 10);
const HOST = process.env.HOST || "0.0.0.0";
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_UPSTREAM_JSON_BYTES = 2 * 1024 * 1024;
const CACHE_TTL_MS = 30 * 60 * 1000;
const MAX_CACHE_ENTRIES = 100;
const MAX_CACHE_BYTES = 2 * 1024 * 1024;
const MAX_ACTIVE_LOOKUPS = 2;
const MAX_ACTIVE_STREAM_REQUESTS = 8;
const MAX_ARCHIVE_ITEMS = 10;
const MAX_FILES_PER_ITEM = 500;
const MAX_SUBTITLES = 5;
const MAX_STREAMS = 5;
const VIDEO_EXTENSIONS = new Set(["avi", "m4v", "mkv", "mov", "mp4", "wmv"]);
const SUBTITLE_EXTENSIONS = new Set(["ass", "srt", "vtt"]);


const manifest = {
  id: "xyz.dimensiondoor.internet-archive",
  version: "1.0.0",
  name: "Internet Archive",
  description: "Direct Internet Archive streams for movies in Stremio",
  resources: ["stream"],
  types: ["movie"],
  idPrefixes: ["tt"],
  catalogs: [],
  behaviorHints: { configurable: false },
};

function extension(name = "") {
  if (typeof name !== "string") return "";
  return name.includes(".") ? name.split(".").pop().toLowerCase() : "";
}

function archiveFileUrl(identifier, name) {
  return `https://archive.org/download/${encodeURIComponent(identifier)}/${encodeURIComponent(name)}`;
}

function escapeLucenePhrase(value) {
  return value.replace(/([\\"])/g, "\\$1");
}

function normalizeTitle(value = "") {
  if (typeof value !== "string") return "";
  return value
    .normalize("NFKD")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .toLowerCase();
}

function matchingFileStem(name = "") {
  return normalizeTitle(
    name
      .replace(/\.[^.]+$/, "")
      .replace(/\.(?:ia|en|eng|english)$/i, ""),
  );
}

async function fetchJsonFromNetwork(url) {
  const response = await fetch(url, {
    headers: { "user-agent": "dimensiondoor-stremio-internet-archive/1.0" },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new Error(`Upstream returned HTTP ${response.status}`);
  }
  return parseJsonResponse(response, MAX_UPSTREAM_JSON_BYTES);
}

async function parseJsonResponse(response, maxBytes) {
  const declaredLength = Number.parseInt(response.headers.get("content-length") || "0", 10);
  if (declaredLength > maxBytes) throw new Error("Upstream JSON body is too large");
  if (!response.body) throw new Error("Upstream returned an empty body");

  const chunks = [];
  let totalBytes = 0;
  for await (const chunk of response.body) {
    totalBytes += chunk.byteLength;
    if (totalBytes > maxBytes) throw new Error("Upstream JSON body is too large");
    chunks.push(Buffer.from(chunk));
  }
  return JSON.parse(Buffer.concat(chunks, totalBytes).toString("utf8"));
}

function chooseVideo(files, minimumLengthSeconds, maximumLengthSeconds) {
  const candidates = files.filter((file) => {
    if (!file || typeof file.name !== "string" || file.name.length > 512) return false;
    const length = Number.parseFloat(file.length || "0");
    return (
      VIDEO_EXTENSIONS.has(extension(file.name)) &&
      length >= minimumLengthSeconds &&
      length <= maximumLengthSeconds
    );
  });
  candidates.sort((left, right) => {
    const leftMp4 = extension(left.name) === "mp4" ? 1 : 0;
    const rightMp4 = extension(right.name) === "mp4" ? 1 : 0;
    if (leftMp4 !== rightMp4) return rightMp4 - leftMp4;
    const leftOriginal = left.source === "original" ? 1 : 0;
    const rightOriginal = right.source === "original" ? 1 : 0;
    if (leftOriginal !== rightOriginal) return rightOriginal - leftOriginal;
    return Number.parseInt(right.height || "0", 10) - Number.parseInt(left.height || "0", 10);
  });
  return candidates[0] || null;
}

function subtitleStreams(identifier, files, videoName) {
  const videoStem = matchingFileStem(videoName);
  const subtitles = [];
  const names = new Set();
  for (const file of files) {
    if (subtitles.length >= MAX_SUBTITLES) break;
    if (!file || typeof file.name !== "string" || file.name.length > 512) continue;
    if (!SUBTITLE_EXTENSIONS.has(extension(file.name))) continue;
    if (matchingFileStem(file.name) !== videoStem || names.has(file.name)) continue;
    names.add(file.name);
    subtitles.push({
      id: file.name,
      lang: "eng",
      url: archiveFileUrl(identifier, file.name),
    });
  }
  return subtitles;
}

async function buildMovieStreams(imdbId, fetchJson = fetchJsonFromNetwork) {
  if (!/^tt\d+$/.test(imdbId)) return { streams: [] };

  const cinemeta = await fetchJson(
    `https://v3-cinemeta.strem.io/meta/movie/${encodeURIComponent(imdbId)}.json`,
  );
  const movie = cinemeta?.meta;
  if (typeof movie?.name !== "string" || !movie.name || movie.name.length > 300) {
    return { streams: [] };
  }

  const runtimeMinutes = Number.parseInt(movie.runtime || "0", 10);
  if (!runtimeMinutes) return { streams: [] };

  const query = `title:("${escapeLucenePhrase(movie.name)}") AND mediatype:movies`;
  const searchUrl = new URL("https://archive.org/advancedsearch.php");
  searchUrl.searchParams.set("q", query);
  searchUrl.searchParams.append("fl[]", "identifier");
  searchUrl.searchParams.append("fl[]", "title");
  searchUrl.searchParams.append("fl[]", "year");
  searchUrl.searchParams.set("rows", String(MAX_ARCHIVE_ITEMS));
  searchUrl.searchParams.set("output", "json");

  const search = await fetchJson(searchUrl.toString());
  const documents = Array.isArray(search?.response?.docs)
    ? search.response.docs.slice(0, MAX_ARCHIVE_ITEMS)
    : [];
  const streams = [];
  let itemFailures = 0;
  const expectedTitle = normalizeTitle(movie.name);
  const movieYear = Number.parseInt(movie.year || "0", 10);
  const minimumLengthSeconds = runtimeMinutes * 60 * 0.7;
  const maximumLengthSeconds = runtimeMinutes * 60 * 1.3;

  for (const document of documents) {
    if (streams.length >= MAX_STREAMS) break;
    try {
      if (
        !document ||
        typeof document.identifier !== "string" ||
        !document.identifier ||
        document.identifier.length > 200 ||
        typeof document.title !== "string" ||
        document.title.length > 300
      ) {
        continue;
      }
      const candidateTitle = normalizeTitle(document.title);
      if (candidateTitle !== expectedTitle && !candidateTitle.startsWith(`${expectedTitle} `)) {
        continue;
      }
      const documentYear = Number.parseInt(document.year || "0", 10);
      if (movieYear && documentYear && Math.abs(movieYear - documentYear) > 1) continue;

      const item = await fetchJson(
        `https://archive.org/metadata/${encodeURIComponent(document.identifier)}`,
      );
      const files = Array.isArray(item?.files)
        ? item.files.slice(0, MAX_FILES_PER_ITEM)
        : [];
      const video = chooseVideo(files, minimumLengthSeconds, maximumLengthSeconds);
      if (!video) continue;

      const fileExtension = extension(video.name);
      const height = Number.parseInt(video.height || "0", 10);
      const size = Number.parseInt(video.size || "0", 10);
      const lengthMinutes = Math.round(Number.parseFloat(video.length || "0") / 60);
      const sourceTitle = document.title;
      const videoFormat =
        typeof video.format === "string" && video.format.length <= 100
          ? video.format
          : fileExtension.toUpperCase();
      const detailParts = [height ? `${height}p` : "", videoFormat]
        .filter(Boolean)
        .join(" · ");

      streams.push({
        name: `📼 Archive.org • ${sourceTitle}${detailParts ? ` • ${detailParts}` : ""}`,
        description: [
          video.name,
          `Runtime: ${lengthMinutes} min`,
          size ? `Size: ${(size / 1073741824).toFixed(1)} GB` : "",
        ].filter(Boolean).join("\n"),
        url: archiveFileUrl(document.identifier, video.name),
        subtitles: subtitleStreams(document.identifier, files, video.name),
        behaviorHints: {
          notWebReady: fileExtension !== "mp4",
          videoSize: size,
          filename: video.name,
        },
      });
    } catch {
      itemFailures += 1;
      continue;
    }
  }

  if (!streams.length && itemFailures) {
    throw new Error("Archive item lookup failed");
  }
  return { streams };
}

function createLookupCache({ maxEntries, maxBytes, ttlMs, maxActive }) {
  const values = new Map();
  const inFlight = new Map();
  let active = 0;
  let totalBytes = 0;

  function remove(key) {
    const entry = values.get(key);
    if (!entry) return;
    totalBytes -= entry.size;
    values.delete(key);
  }

  function pruneExpired(now) {
    for (const [key, entry] of values) {
      if (entry.expiresAt <= now) remove(key);
    }
  }

  function makeRoom(incomingBytes) {
    while (values.size && (values.size >= maxEntries || totalBytes + incomingBytes > maxBytes)) {
      remove(values.keys().next().value);
    }
  }

  function get(key, loader) {
    const now = Date.now();
    pruneExpired(now);
    const cached = values.get(key);
    if (cached) {
      values.delete(key);
      values.set(key, cached);
      return Promise.resolve(cached.value);
    }
    if (inFlight.has(key)) return inFlight.get(key);
    if (active >= maxActive) return Promise.reject(new Error("lookup service is busy"));

    active += 1;
    const request = Promise.resolve()
      .then(loader)
      .then((value) => {
        const size = Buffer.byteLength(JSON.stringify(value));
        pruneExpired(Date.now());
        makeRoom(size);
        if (size <= maxBytes) {
          values.set(key, { value, size, expiresAt: Date.now() + ttlMs });
          totalBytes += size;
        }
        return value;
      })
      .finally(() => {
        active -= 1;
        inFlight.delete(key);
      });
    inFlight.set(key, request);
    return request;
  }

  return { bytes: () => totalBytes, get, size: () => values.size };
}

const lookupCache = createLookupCache({
  maxEntries: MAX_CACHE_ENTRIES,
  maxBytes: MAX_CACHE_BYTES,
  ttlMs: CACHE_TTL_MS,
  maxActive: MAX_ACTIVE_LOOKUPS,
});

function createRequestGate(maxActive) {
  let active = 0;

  async function run(task) {
    if (active >= maxActive) throw new Error("Too many active stream requests");
    active += 1;
    try {
      return await task();
    } finally {
      active -= 1;
    }
  }

  return { active: () => active, run };
}

const requestGate = createRequestGate(MAX_ACTIVE_STREAM_REQUESTS);

function cachedMovieStreams(imdbId) {
  return lookupCache.get(imdbId, () => buildMovieStreams(imdbId));
}

function sendJson(response, status, value, cacheControl = "public, max-age=300") {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "access-control-allow-origin": "*",
    "cache-control": cacheControl,
    "content-length": Buffer.byteLength(body),
    "content-type": "application/json; charset=utf-8",
  });
  response.end(body);
}

async function handleRequest(request, response) {
  const url = new URL(request.url || "/", "http://localhost");

  if (request.method === "OPTIONS") {
    response.writeHead(204, {
      "access-control-allow-methods": "GET, OPTIONS",
      "access-control-allow-origin": "*",
      "content-length": "0",
    });
    response.end();
    return;
  }
  if (request.method !== "GET") {
    sendJson(response, 405, { error: "Method not allowed" });
    return;
  }
  if (url.pathname === "/health") {
    sendJson(response, 200, { status: "ok" });
    return;
  }
  if (url.pathname === "/manifest.json") {
    sendJson(response, 200, manifest);
    return;
  }

  const streamMatch = url.pathname.match(/^\/stream\/movie\/(tt\d+)\.json$/);
  if (streamMatch) {
    try {
      const streams = await requestGate.run(() => cachedMovieStreams(streamMatch[1]));
      sendJson(response, 200, streams);
    } catch (error) {
      console.error("stream lookup failed", error?.message || error);
      sendJson(response, 200, { streams: [] }, "no-store");
    }
    return;
  }

  sendJson(response, 404, { error: "Not found" });
}

if (require.main === module) {
  http.createServer(handleRequest).listen(PORT, HOST, () => {
    console.log(`Internet Archive Stremio add-on listening on ${HOST}:${PORT}`);
  });
}

module.exports = {
  buildMovieStreams,
  chooseVideo,
  createLookupCache,
  createRequestGate,
  handleRequest,
  manifest,
  parseJsonResponse,
};
