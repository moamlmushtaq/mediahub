import Foundation

/// The decisions a player makes that are not about drawing anything.
///
/// Both types here could just as easily have been written inside the SwiftUI
/// player view, and that is exactly why they are not: they are the parts with
/// rules, and rules are what tests are for. What is left in the view is the
/// AVPlayer plumbing, which a test could not check anyway.

// MARK: - Choosing a subtitle track

public enum SubtitlePicker {
    /// Three-letter codes to two, for the languages this library holds and the
    /// common ones besides.
    ///
    /// The catalog takes these from filenames, so **both** forms occur in the
    /// same folder: `ara.srt` sits next to `English.srt`, and one release will
    /// say `fre` where another says `fr`. Without this table a viewer whose
    /// remembered choice is `en` never matches a track tagged `eng`, and the
    /// app quietly ignores the preference it just saved.
    ///
    /// Unlisted codes pass through unchanged, so an unusual language still
    /// matches itself.
    static let twoLetter: [String: String] = [
        "ara": "ar", "arb": "ar", "eng": "en", "fre": "fr", "fra": "fr",
        "ger": "de", "deu": "de", "spa": "es", "por": "pt", "ita": "it",
        "dut": "nl", "nld": "nl", "cze": "cs", "ces": "cs", "dan": "da",
        "swe": "sv", "nor": "no", "nob": "no", "fin": "fi", "pol": "pl",
        "rus": "ru", "tur": "tr", "gre": "el", "ell": "el", "heb": "he",
        "hun": "hu", "rum": "ro", "ron": "ro", "bul": "bg", "hrv": "hr",
        "srp": "sr", "slo": "sk", "slk": "sk", "slv": "sl", "est": "et",
        "lav": "lv", "lit": "lt", "ukr": "uk", "per": "fa", "fas": "fa",
        "hin": "hi", "tha": "th", "vie": "vi", "ind": "id", "may": "ms",
        "msa": "ms", "kor": "ko", "jpn": "ja", "chi": "zh", "zho": "zh",
    ]

    /// Normalises a language tag to its base language, lowercased.
    ///
    /// `ar-SA`, `AR`, `ara` all describe the same subtitle as far as picking a
    /// default goes — and so do `en` and `eng`.
    public static func language(_ tag: String?) -> String? {
        guard let tag, !tag.isEmpty else { return nil }
        let base = String(tag.lowercased().split(separator: "-").first ?? "")
        guard !base.isEmpty else { return nil }
        return twoLetter[base] ?? base
    }

    /// Which track to switch on when playback begins.
    ///
    /// In order: what this viewer chose last time, then whatever the server
    /// marked as default, then Arabic, then nothing.
    ///
    /// **A forced track is never chosen automatically.** "Forced" means the
    /// file contains only the signs and the foreign-language lines — the parts
    /// that must be readable even when you understand the spoken language.
    /// Switching it on as *the* subtitle track leaves most of the film with no
    /// subtitles at all, and it does it silently: the viewer sees subtitles
    /// appear at the start, trusts them, and then sits through an untranslated
    /// hour wondering what broke.
    public static func preferred(
        from tracks: [SubtitleTrack],
        remembering remembered: String? = nil
    ) -> SubtitleTrack? {
        let selectable = tracks.filter { !$0.forced }
        guard !selectable.isEmpty else { return nil }

        if let wanted = language(remembered),
           let match = selectable.first(where: { language($0.language) == wanted }) {
            return match
        }

        if let marked = selectable.first(where: \.isDefault) {
            return marked
        }

        if let ar = selectable.first(where: { language($0.language) == "ar" }) {
            return ar
        }

        return nil
    }

    /// The forced track that pairs with a chosen audio language, if there is one.
    ///
    /// Kept separate from ``preferred(from:remembering:)`` because a forced
    /// track is an addition to the picture, not a choice of subtitle — a player
    /// may want to show it even when full subtitles are switched off.
    public static func forced(from tracks: [SubtitleTrack], language wanted: String?) -> SubtitleTrack? {
        let target = language(wanted)
        return tracks.first { $0.forced && (target == nil || language($0.language) == target) }
    }
}

// MARK: - Deciding when to save the position

/// Throttles progress reports.
///
/// Two failures this prevents, and the second is the expensive one:
///
/// 1. **Spam.** A player publishes its time many times a second. Forwarding
///    that is a request per frame to a box that is also serving a website.
///
/// 2. **Erasing the resume point.** This is the one that actually bites. An
///    AVPlayer reports `currentTime == 0` from the moment an item is attached
///    until the seek to the saved position completes. If a routine tick fires
///    in that window, the app helpfully saves "position: 0" over the very
///    resume point it is about to jump to — and the bug only shows the *next*
///    time the viewer opens that film, which makes it almost impossible to
///    connect to what caused it. So a routine tick at zero reports nothing.
public struct ProgressReporter: Sendable {
    /// What prompted the question.
    public enum Moment: Sendable, Equatable {
        /// The player's periodic time observer.
        case tick
        /// The viewer paused, or playback stalled.
        case paused
        /// The viewer jumped somewhere.
        case seeked
        /// The item ended, or the window closed.
        case finished
    }

    /// Seconds between routine reports. Ten is frequent enough that closing a
    /// laptop lid loses at most ten seconds of position, and rare enough to be
    /// invisible in the server's logs.
    public let interval: Double

    private var lastPosition: Ticks?
    private var lastReportAt: Double?

    public init(interval: Double = 10) {
        self.interval = interval
    }

    /// - Parameter now: A monotonic clock reading in seconds. Injected rather
    ///   than read from `Date()` so the rules can be tested without waiting.
    public mutating func shouldReport(position: Ticks, moment: Moment, now: Double) -> Bool {
        // Nothing was learned since the last report.
        if let lastPosition, lastPosition == position, moment != .finished {
            return false
        }

        switch moment {
        case .tick:
            // See the note above: this is the resume-point eraser.
            guard position.rawValue > 0 else { return false }
            guard let lastReportAt else {
                accept(position, at: now)
                return true
            }
            guard now - lastReportAt >= interval else { return false }
            accept(position, at: now)
            return true

        case .paused, .seeked, .finished:
            // These are the moments worth recording exactly, so they bypass the
            // interval — but not the "nothing changed" check above.
            accept(position, at: now)
            return true
        }
    }

    private mutating func accept(_ position: Ticks, at now: Double) {
        lastPosition = position
        lastReportAt = now
    }

    /// Forgets everything. Call when the player moves to a different item, or
    /// the next film inherits this one's throttle and its first position is
    /// dropped as a duplicate.
    public mutating func reset() {
        lastPosition = nil
        lastReportAt = nil
    }
}
