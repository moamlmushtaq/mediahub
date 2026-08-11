import Foundation

/// Reading subtitle files, and finding the line that belongs on screen.
///
/// WHY THIS IS HAND-WRITTEN AND NOT HANDED TO AVFOUNDATION
/// ======================================================
/// AVPlayer will not load an external subtitle file. It reads tracks that are
/// inside the asset, or `EXT-X-MEDIA` tracks declared in an HLS playlist —
/// neither of which applies here, because this library's subtitles are loose
/// `.srt` files sitting next to the video in a `Subs/` folder, fetched from
/// Bunny under their own signed URLs.
///
/// So the app parses them and draws them itself. That is not a workaround with
/// a cost; it is the same thing the website does, and it buys back the control
/// AVPlayer's built-in rendering does not give: font size, background opacity,
/// vertical position, and Arabic that is shaped and aligned the way the rest of
/// the app shapes it.
///
/// WHAT MAKES REAL FILES HARD
/// ==========================
/// Every rule below was put there by a file that actually exists in this
/// library, not by the specification:
///
/// * **Windows-1256.** Arabic subtitles from scene releases are very often
///   written in the Windows Arabic code page, not UTF-8. Decoded as UTF-8 they
///   either fail outright or turn into mojibake, and the viewer sees a row of
///   question marks. There is no declaration in the file; it has to be guessed.
/// * **A byte-order mark** on the first cue number, which stops `Int(...)`
///   parsing it and silently drops the first line of dialogue.
/// * **CRLF**, because these files come from everywhere.
/// * **Markup**: `<i>`, `<b>`, `<font color=…>`, and SubStation overrides like
///   `{\an8}` that mean "put this at the top" and must not be printed.
/// * **Overlapping cues**, where two lines are legitimately on screen at once.

// MARK: - Cue

/// One subtitle line, with the window of time it belongs to.
public struct Cue: Hashable, Sendable, Identifiable {
    public let id: Int
    /// Seconds from the start of the file.
    public let start: Double
    public let end: Double
    /// The text, already stripped of markup. May contain newlines.
    public let text: String

    public init(id: Int, start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }

    public func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

// MARK: - Track

/// A parsed subtitle file, ready to be asked what belongs on screen.
public struct SubtitleDocument: Sendable {
    public let cues: [Cue]

    public init(cues: [Cue]) {
        // Sorted once, here, so every lookup afterwards can binary search.
        // Subtitle files are usually already in order, but "usually" is not a
        // property a search can rely on.
        self.cues = cues.sorted { $0.start < $1.start }
    }

    public var isEmpty: Bool { cues.isEmpty }

    /// The cues that should be on screen at `time`.
    ///
    /// Returns an array rather than a single cue because overlapping cues are
    /// legal and common — a sign being translated while a character speaks.
    /// Rendering only the first would drop half of some scenes.
    ///
    /// Binary search rather than a linear scan: this runs on every frame
    /// callback of the player, and a film has thousands of cues.
    public func cues(at time: Double) -> [Cue] {
        guard !cues.isEmpty else { return [] }

        // Find the first cue that starts after `time`; everything that can
        // possibly be on screen begins at or before that point.
        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { low = mid + 1 } else { high = mid }
        }

        // Walk back over cues that are still open. The window is bounded
        // because a cue that started long ago has long since ended; ten is far
        // beyond any real overlap and stops a pathological file from making
        // this linear.
        var result: [Cue] = []
        var index = low - 1
        var examined = 0
        while index >= 0, examined < 10 {
            let cue = cues[index]
            if cue.contains(time) { result.append(cue) }
            index -= 1
            examined += 1
        }
        return result.reversed()
    }
}

// MARK: - Parsing

public enum SubtitleParser {
    /// Decodes bytes into text, guessing the encoding the way real files need.
    ///
    /// UTF-8 is tried first because it is correct when it works and *fails*
    /// when it does not: the byte sequences Arabic Windows-1256 produces are
    /// not valid UTF-8, so a strict decode rejects them rather than quietly
    /// returning something wrong. That makes the failure a reliable signal, and
    /// the fallback is the code page those files are actually written in.
    ///
    /// See ``WindowsArabic`` for why that table is here rather than Foundation's.
    public static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return WindowsArabic.decode(data)
    }

    /// Parses SubRip or WebVTT. The format is detected, not declared.
    ///
    /// Detection rather than a parameter because the server's type says these
    /// tracks are WebVTT and every file in the library is actually SubRip. When
    /// the contract and the data disagree, trust the data — and then handle
    /// both, since the difference is two characters of timestamp separator.
    public static func parse(_ raw: String) -> SubtitleDocument {
        var text = raw

        // A BOM on the first line stops the first cue number parsing, which
        // costs exactly one line of dialogue — the kind of bug nobody reports
        // because nobody knows they missed anything.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        var cues: [Cue] = []
        var nextID = 0

        for block in text.components(separatedBy: "\n\n") {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else { continue }
            // WebVTT's header, and its comment and style blocks, are not cues.
            if lines[0].hasPrefix("WEBVTT") || lines[0].hasPrefix("NOTE") || lines[0].hasPrefix("STYLE") {
                continue
            }

            // The timing line is the one with an arrow. It is not always the
            // first: SubRip puts a sequence number above it, WebVTT allows an
            // optional cue identifier, and both are ignorable.
            guard let arrowIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let (start, end) = parseTiming(lines[arrowIndex]),
                  end > start
            else { continue }

            let body = lines[(arrowIndex + 1)...].joined(separator: "\n")
            let cleaned = strip(body)
            guard !cleaned.isEmpty else { continue }

            cues.append(Cue(id: nextID, start: start, end: end, text: cleaned))
            nextID += 1
        }

        return SubtitleDocument(cues: cues)
    }

    public static func parse(_ data: Data) -> SubtitleDocument {
        parse(decode(data))
    }

    /// `00:01:02,345 --> 00:01:05,000`, with WebVTT's `.` accepted for `,`
    /// and WebVTT's trailing cue settings (`line:90% align:center`) ignored.
    static func parseTiming(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        let left = parts[0].trimmingCharacters(in: .whitespaces)
        // Anything after the end stamp is a cue setting, not part of the time.
        let right = parts[1]
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)[0]

        guard let start = parseTimestamp(left), let end = parseTimestamp(right) else { return nil }
        return (start, end)
    }

    /// `HH:MM:SS,mmm` or `MM:SS.mmm` — WebVTT makes the hour optional.
    static func parseTimestamp(_ stamp: String) -> Double? {
        let normalised = stamp.replacingOccurrences(of: ",", with: ".")
        let pieces = normalised.components(separatedBy: ":")
        guard (2...3).contains(pieces.count) else { return nil }

        var seconds = 0.0
        for piece in pieces {
            guard let value = Double(piece), value >= 0 else { return nil }
            seconds = seconds * 60 + value
        }
        return seconds
    }

    /// Removes what is markup and keeps what is dialogue.
    static func strip(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)

        var inTag = false
        var inBrace = false

        for character in text {
            switch character {
            case "<" where !inBrace:
                inTag = true
            case ">" where inTag:
                inTag = false
            // `{\an8}` and friends: SubStation positioning that leaked into an
            // SRT. Printing it puts literal braces on screen mid-sentence.
            case "{" where !inTag:
                inBrace = true
            case "}" where inBrace:
                inBrace = false
            default:
                if !inTag && !inBrace { output.append(character) }
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
