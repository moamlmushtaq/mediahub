import Foundation
import Testing
@testable import MediaHubKit

/// Builds a track without going through the decoder.
private func track(
    _ label: String,
    language: String?,
    forced: Bool = false,
    isDefault: Bool = false
) throws -> SubtitleTrack {
    let json = """
    {"url":"https://cdn.invalid/\(label).srt","language":\(language.map { "\"\($0)\"" } ?? "null"),
     "label":"\(label)","forced":\(forced),"isDefault":\(isDefault)}
    """
    return try JSONDecoder().decode(SubtitleTrack.self, from: Data(json.utf8))
}

@Suite("Choosing a subtitle track")
struct SubtitlePickerTests {
    @Test("normalises the language codes the catalog actually stores")
    func normalises() {
        // The catalog takes these from filenames, so all of them occur.
        #expect(SubtitlePicker.language("ar") == "ar")
        #expect(SubtitlePicker.language("ara") == "ar")
        #expect(SubtitlePicker.language("arb") == "ar")
        #expect(SubtitlePicker.language("ar-SA") == "ar")
        #expect(SubtitlePicker.language("AR") == "ar")
        #expect(SubtitlePicker.language("en-GB") == "en")
        #expect(SubtitlePicker.language(nil) == nil)
        #expect(SubtitlePicker.language("") == nil)
    }

    @Test("prefers what the viewer chose last time")
    func remembersChoice() throws {
        let tracks = [
            try track("العربية", language: "ara", isDefault: true),
            try track("English", language: "eng"),
        ]
        let chosen = SubtitlePicker.preferred(from: tracks, remembering: "en")
        #expect(chosen?.label == "English")
    }

    @Test("falls back to the server's default")
    func usesDefault() throws {
        let tracks = [
            try track("English", language: "eng"),
            try track("Français", language: "fre", isDefault: true),
        ]
        #expect(SubtitlePicker.preferred(from: tracks)?.label == "Français")
    }

    @Test("falls back to Arabic")
    func prefersArabic() throws {
        let tracks = [
            try track("English", language: "eng"),
            try track("العربية", language: "ara"),
        ]
        #expect(SubtitlePicker.preferred(from: tracks)?.label == "العربية")
    }

    @Test("switches nothing on when there is no reason to")
    func nothingToPick() throws {
        let tracks = [
            try track("Danish", language: "dan"),
            try track("Czech", language: "cze"),
        ]
        #expect(SubtitlePicker.preferred(from: tracks) == nil)
        #expect(SubtitlePicker.preferred(from: []) == nil)
    }

    @Test("never auto-selects a forced track")
    func neverAutoSelectsForced() throws {
        // The failure this prevents is silent and slow: forced subtitles appear
        // at the start, the viewer trusts them, and then most of the film has
        // no subtitles at all.
        let tracks = [
            try track("العربية (علامات)", language: "ara", forced: true, isDefault: true),
            try track("English", language: "eng"),
        ]

        // Nothing is switched on. The forced track is refused, and English is
        // not offered in its place: picking a language nobody asked for is a
        // guess, and the viewer can choose in one click.
        #expect(SubtitlePicker.preferred(from: tracks) == nil)

        // Not even when it is the only Arabic track and Arabic is remembered.
        #expect(SubtitlePicker.preferred(from: tracks, remembering: "ar") == nil)
    }

    @Test("matches two-letter and three-letter codes as the same language")
    func codeForms() {
        // Both forms sit in the same folder in this library: `ara.srt` next to
        // `English.srt`. Without this, a saved preference silently stops
        // matching the track it was saved from.
        #expect(SubtitlePicker.language("eng") == "en")
        #expect(SubtitlePicker.language("fre") == SubtitlePicker.language("fra"))
        #expect(SubtitlePicker.language("cze") == "cs")
        // Unknown codes match themselves rather than disappearing.
        #expect(SubtitlePicker.language("xyz") == "xyz")
    }

    @Test("finds a forced track when one is asked for explicitly")
    func findsForced() throws {
        let tracks = [
            try track("English", language: "eng"),
            try track("العربية (علامات)", language: "ara", forced: true),
        ]
        #expect(SubtitlePicker.forced(from: tracks, language: "ar")?.label == "العربية (علامات)")
        #expect(SubtitlePicker.forced(from: tracks, language: "en") == nil)
    }

    @Test("ignores a remembered language that is not on offer")
    func rememberedMissing() throws {
        let tracks = [try track("العربية", language: "ara")]
        // Falls through to the Arabic rule rather than returning nothing.
        #expect(SubtitlePicker.preferred(from: tracks, remembering: "de")?.label == "العربية")
    }
}

@Suite("Reporting progress")
struct ProgressReporterTests {
    @Test("does not erase the resume point at position zero")
    func neverReportsZeroOnATick() {
        // The bug this exists to prevent: AVPlayer reports 0 between attaching
        // an item and completing the seek to the saved position. Saving that
        // overwrites the resume point with zero, and it only shows up the next
        // time the film is opened.
        var reporter = ProgressReporter()
        let r1 = reporter.shouldReport(position: .zero, moment: .tick, now: 0)
        #expect(!r1)
        let r2 = reporter.shouldReport(position: .zero, moment: .tick, now: 60)
        #expect(!r2)
    }

    @Test("reports the first real position immediately")
    func firstPosition() {
        var reporter = ProgressReporter()
        let r3 = reporter.shouldReport(position: Ticks(seconds: 5), moment: .tick, now: 5)
        #expect(r3)
    }

    @Test("throttles routine ticks to the interval")
    func throttles() {
        var reporter = ProgressReporter(interval: 10)
        let r4 = reporter.shouldReport(position: Ticks(seconds: 1), moment: .tick, now: 100)
        #expect(r4)
        let r5 = reporter.shouldReport(position: Ticks(seconds: 2), moment: .tick, now: 103)
        #expect(!r5)
        let r6 = reporter.shouldReport(position: Ticks(seconds: 3), moment: .tick, now: 109.9)
        #expect(!r6)
        let r7 = reporter.shouldReport(position: Ticks(seconds: 4), moment: .tick, now: 110)
        #expect(r7)
    }

    @Test("reports a pause, a seek and an ending without waiting")
    func importantMoments() {
        var reporter = ProgressReporter(interval: 10)
        let r8 = reporter.shouldReport(position: Ticks(seconds: 100), moment: .tick, now: 0)
        #expect(r8)
        // One second later — a tick would be throttled, but these must not be.
        let r9 = reporter.shouldReport(position: Ticks(seconds: 101), moment: .paused, now: 1)
        #expect(r9)
        let r10 = reporter.shouldReport(position: Ticks(seconds: 400), moment: .seeked, now: 2)
        #expect(r10)
        let r11 = reporter.shouldReport(position: Ticks(seconds: 401), moment: .finished, now: 3)
        #expect(r11)
    }

    @Test("says nothing when nothing changed")
    func noRepeats() {
        var reporter = ProgressReporter(interval: 10)
        let position = Ticks(seconds: 250)
        let r12 = reporter.shouldReport(position: position, moment: .tick, now: 0)
        #expect(r12)
        // A paused player keeps ticking at the same position; re-sending it is
        // a request that teaches the server nothing.
        let r13 = reporter.shouldReport(position: position, moment: .tick, now: 30)
        #expect(!r13)
        let r14 = reporter.shouldReport(position: position, moment: .paused, now: 31)
        #expect(!r14)
    }

    @Test("always reports the end, even at an unchanged position")
    func finishedAlwaysReports() {
        // Closing the window on a paused player must still commit the position.
        var reporter = ProgressReporter()
        let position = Ticks(seconds: 250)
        let r15 = reporter.shouldReport(position: position, moment: .tick, now: 0)
        #expect(r15)
        let r16 = reporter.shouldReport(position: position, moment: .finished, now: 1)
        #expect(r16)
    }

    @Test("reports a seek backwards")
    func seekBackwards() {
        var reporter = ProgressReporter(interval: 10)
        let r17 = reporter.shouldReport(position: Ticks(seconds: 900), moment: .tick, now: 0)
        #expect(r17)
        let r18 = reporter.shouldReport(position: Ticks(seconds: 60), moment: .seeked, now: 1)
        #expect(r18)
    }

    @Test("forgets the previous item")
    func resetsBetweenItems() {
        // Without this the next film's opening position looks like a duplicate
        // of the last one's and is dropped.
        var reporter = ProgressReporter(interval: 10)
        let position = Ticks(seconds: 120)
        let r19 = reporter.shouldReport(position: position, moment: .tick, now: 0)
        #expect(r19)
        let r20 = reporter.shouldReport(position: position, moment: .tick, now: 1)
        #expect(!r20)

        reporter.reset()
        let r21 = reporter.shouldReport(position: position, moment: .tick, now: 2)
        #expect(r21)
    }
}
