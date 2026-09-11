# Internet Archive Stremio add-on

This private stream add-on searches Internet Archive from existing Stremio movie pages. It does not add a catalog.

## Install

After the GitOps rollout and DNS update complete, install this manifest in Stremio:

```text
https://archive-stremio.dimensiondoor.xyz/manifest.json
```

## Matching

- Accepts movie IMDb IDs from Cinemeta.
- Searches Internet Archive by the Cinemeta title.
- Checks normalized titles and known years.
- Checks a 70–130 percent runtime range.

## Output

- Returns one complete video from each matching Archive item.
- Prefers original MP4 files.
- Returns at most five streams.
- Streams files directly from Archive.org.

## Resource limits

- Caches at most 100 results and 2 MiB for 30 minutes.
- Rejects upstream JSON above 2 MiB.
- Checks at most 500 files per Archive item.
- Returns at most five subtitles per Archive item.
- Runs at most two upstream lookups and eight stream requests at once.

## Limits

Internet Archive search results can contain false matches. Archive collection names do not prove copyright or license status. Check the item metadata before playback.

The add-on attaches only sidecar subtitles that match the selected video filename. It marks them as English because Archive metadata lacks reliable per-file language data.

## Test

```bash
node --test test.js
node app.js
curl http://127.0.0.1:7000/stream/movie/tt0257497.json
```
