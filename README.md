# MediaHub for macOS

A native Mac client for a self-hosted media library, written in Swift.

> **Status:** `MediaHubKit` — the API client, subtitle engine and playback logic —
> is complete and tested. The SwiftUI/AVKit app layer on top of it is in
> progress.

---

## The idea it is built around

The server this talks to owns a library, accounts, metadata and subtitles. It
does **not** own video. Files live on a CDN, and the server's only role at
playback time is to check who is asking and mint a signed URL that expires in a
few hours. The bytes go from the CDN to the viewer's machine directly.

That constraint is what makes the whole system affordable to run — a shared
4-vCPU box can serve a dozen households because it never touches a video frame —
and this client keeps it: `AVPlayer` is handed the signed URL and fetches the
media itself.

## Why the package is split in two

```
Sources/
  MediaHubKit/     no AppKit, no SwiftUI, no AVFoundation — builds anywhere
  MediaHub/        SwiftUI + AVKit — needs a Mac
```

This is not architectural decoration. It is developed on a Linux server, where
Swift compiles but Apple's frameworks do not exist. Putting every piece of
*logic* below the platform line means the parts that are actually easy to get
wrong — JSON decoding, subtitle timing, resume arithmetic, URL construction —
have real tests that run on every commit, instead of being verified by opening
the app and squinting.

CI enforces the line: a Linux job builds and tests the kit, and fails if
`MediaHubKit` ever grows an `import AppKit`.

## What is in the kit

| File | Responsibility |
|---|---|
| `APIClient.swift` | An `actor` wrapping the REST API, with an injectable transport so it is testable without a server |
| `Models.swift` | The wire types, with a deliberate strict/lenient split (see below) |
| `Subtitles.swift` | SubRip and WebVTT parsing, and cue lookup by playback time |
| `WindowsArabic.swift` | A Windows-1256 decoding table |
| `Ticks.swift` | Timeline positions and the resume rules |
| `Artwork.swift` | Poster and backdrop URLs |

### Decoding: strict about identity, lenient about everything else

A record with no `id` is dropped — it would draw a row that cannot be opened. A
record with no summary, year, rating or artwork is kept, because a personal
library is full of files no metadata provider has ever heard of, and a client
that refuses to draw them is useless for the collection it exists to show.

Lists decode **element by element**. The obvious implementation — wrapping the
whole array in `try?` — means one malformed record silently empties a page of
sixty, and the symptom it produces ("the library is empty") points at the
server, the network and the account, at everything except the one record
actually responsible. There is a test for this.

### Subtitles are parsed, not delegated

`AVPlayer` will not load an external subtitle file; it reads tracks embedded in
the asset or declared in an HLS playlist. This library's subtitles are loose
`.srt` files fetched from the CDN under their own signed URLs, so the app parses
and draws them itself — which also buys back control of size, background and
position that `AVPlayer`'s own rendering does not offer.

Every rule in the parser comes from a file that exists rather than from the
specification: byte-order marks that swallow the first line of dialogue, CRLF,
`{\an8}` positioning overrides, overlapping cues, and Arabic written in
Windows-1256 rather than UTF-8. That last one is decoded from a table in this
repository because `String.Encoding` has no `windowsCP1256` on Linux and only
reaches it through CoreFoundation on macOS — a difference that would mean
subtitle handling could not be tested where the project is developed.

## Building

```bash
swift test                        # the kit, anywhere Swift runs
swift build -c release            # the app, on a Mac
```

Requires Swift 6.2. The kit builds on Linux and macOS; the app target requires
macOS 14 or later.

## Configuration

The client takes its host as a parameter — there is no hard-coded server, and no
credential of any kind lives in this repository.

```swift
let client = MediaHubClient(baseURL: URL(string: "https://example.com")!)
let session = try await client.logIn(username: "…", password: "…")
```

## Licence

MIT. See [LICENSE](LICENSE).
