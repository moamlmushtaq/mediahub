import Foundation
import Testing
@testable import MediaHubKit

/// Every case here comes from a shape that exists in real subtitle files, not
/// from the SubRip specification — which is barely a specification and which
/// almost nothing in the wild follows exactly.
@Suite("Subtitle parsing")
struct SubtitleParsingTests {
    @Test("reads an ordinary SubRip file")
    func basicSRT() {
        let doc = SubtitleParser.parse("""
        1
        00:00:01,000 --> 00:00:04,000
        First line.

        2
        00:00:05,500 --> 00:00:08,250
        Second line,
        over two rows.
        """)

        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].start == 1.0)
        #expect(doc.cues[0].end == 4.0)
        #expect(doc.cues[0].text == "First line.")
        #expect(doc.cues[1].start == 5.5)
        #expect(doc.cues[1].text == "Second line,\nover two rows.")
    }

    @Test("survives CRLF line endings")
    func crlf() {
        let doc = SubtitleParser.parse("1\r\n00:00:01,000 --> 00:00:02,000\r\nHello\r\n\r\n")
        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].text == "Hello")
    }

    @Test("does not lose the first cue to a byte-order mark")
    func bom() {
        // The classic silent failure: the BOM sticks to the sequence number,
        // the block still parses, and nobody notices one missing line.
        let doc = SubtitleParser.parse("\u{FEFF}1\n00:00:01,000 --> 00:00:02,000\nFirst\n")
        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].text == "First")
    }

    @Test("reads WebVTT, header and all")
    func webVTT() {
        let doc = SubtitleParser.parse("""
        WEBVTT

        NOTE this comment is not dialogue

        intro
        00:00:01.000 --> 00:00:03.000 line:90% align:center
        Spoken words.
        """)

        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].start == 1.0)
        #expect(doc.cues[0].end == 3.0)
        // The cue settings after the end stamp must not end up in the text or
        // in the timing.
        #expect(doc.cues[0].text == "Spoken words.")
    }

    @Test("accepts a timestamp with no hour")
    func shortTimestamp() {
        #expect(SubtitleParser.parseTimestamp("01:30.500") == 90.5)
        #expect(SubtitleParser.parseTimestamp("00:01:30,500") == 90.5)
        #expect(SubtitleParser.parseTimestamp("1:00:00,000") == 3600)
    }

    @Test("rejects a timestamp that is not one")
    func badTimestamp() {
        #expect(SubtitleParser.parseTimestamp("nonsense") == nil)
        #expect(SubtitleParser.parseTimestamp("00:00:00:00:00") == nil)
        #expect(SubtitleParser.parseTimestamp("") == nil)
    }

    @Test("strips markup and SubStation overrides")
    func markup() {
        #expect(SubtitleParser.strip("<i>italic</i>") == "italic")
        #expect(SubtitleParser.strip("<font color=\"#ffffff\">white</font>") == "white")
        // `{\\an8}` means "top of frame". It is an instruction, not dialogue —
        // printing it puts literal braces in the middle of a sentence.
        #expect(SubtitleParser.strip("{\\an8}Top of frame") == "Top of frame")
        #expect(SubtitleParser.strip("<b>bold</b> and {\\i1}more{\\i0}") == "bold and more")
    }

    @Test("skips blocks that carry no dialogue")
    func emptyBlocks() {
        // A timing line with nothing under it is common at the end of files
        // and would otherwise become a cue that blanks the screen.
        let doc = SubtitleParser.parse("""
        1
        00:00:01,000 --> 00:00:02,000

        2
        00:00:03,000 --> 00:00:04,000
        Real line
        """)
        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].text == "Real line")
    }

    @Test("skips a cue that ends before it starts")
    func invertedCue() {
        let doc = SubtitleParser.parse("""
        1
        00:00:05,000 --> 00:00:02,000
        Backwards

        2
        00:00:06,000 --> 00:00:07,000
        Forwards
        """)
        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].text == "Forwards")
    }

    @Test("puts cues in order even when the file is not")
    func sortsOutOfOrder() {
        let doc = SubtitleParser.parse("""
        1
        00:00:10,000 --> 00:00:12,000
        Later

        2
        00:00:01,000 --> 00:00:03,000
        Earlier
        """)
        #expect(doc.cues.map(\.text) == ["Earlier", "Later"])
    }
}

@Suite("Windows-1256 decoding")
struct ArabicEncodingTests {
    @Test("decodes Arabic written in the Windows code page")
    func decodesArabic() {
        // "مرحبا" as a Windows-1256 file would hold it.
        let data = Data([0xE3, 0xD1, 0xCD, 0xC8, 0xC7])
        #expect(SubtitleParser.decode(data) == "مرحبا")
    }

    @Test("prefers UTF-8 when the file is UTF-8")
    func prefersUTF8() {
        let utf8 = Data("مرحبا".utf8)
        #expect(SubtitleParser.decode(utf8) == "مرحبا")
    }

    @Test("keeps ASCII untouched below 0x80")
    func asciiRange() {
        let data = Data("Hello, world!".utf8)
        #expect(WindowsArabic.decode(data) == "Hello, world!")
    }

    @Test("keeps the invisible marks that change layout")
    func directionalMarks() {
        // 0xFD and 0xFE are the LTR and RTL marks. They draw nothing, and
        // dropping them re-orders mixed Arabic/Latin lines on screen.
        #expect(WindowsArabic.decode(Data([0xFD])) == "\u{200E}")
        #expect(WindowsArabic.decode(Data([0xFE])) == "\u{200F}")
        #expect(WindowsArabic.decode(Data([0x9D])) == "\u{200C}")
    }

    @Test("parses an Arabic subtitle end to end from raw bytes")
    func endToEnd() {
        var bytes: [UInt8] = Array("1\n00:00:01,000 --> 00:00:04,000\n".utf8)
        bytes += [0xE3, 0xD1, 0xCD, 0xC8, 0xC7]   // مرحبا
        let doc = SubtitleParser.parse(Data(bytes))
        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].text == "مرحبا")
    }
}

@Suite("Cue lookup")
struct CueLookupTests {
    private let doc = SubtitleParser.parse("""
    1
    00:00:01,000 --> 00:00:03,000
    A

    2
    00:00:02,000 --> 00:00:05,000
    B overlapping A

    3
    00:00:10,000 --> 00:00:12,000
    C
    """)

    @Test("finds the cue on screen")
    func findsCue() {
        #expect(doc.cues(at: 1.5).map(\.text) == ["A"])
        #expect(doc.cues(at: 11).map(\.text) == ["C"])
    }

    @Test("returns both cues when two overlap")
    func overlapping() {
        // Legal and common: a sign being translated while a character speaks.
        // Returning only one drops half of some scenes.
        #expect(doc.cues(at: 2.5).map(\.text) == ["A", "B overlapping A"])
    }

    @Test("shows nothing in the gaps")
    func gaps() {
        #expect(doc.cues(at: 0.5).isEmpty)
        #expect(doc.cues(at: 7).isEmpty)
        #expect(doc.cues(at: 100).isEmpty)
    }

    @Test("is exclusive at the end and inclusive at the start")
    func boundaries() {
        // Off-by-one here shows as a subtitle flickering back for one frame.
        #expect(doc.cues(at: 1.0).map(\.text) == ["A"])
        #expect(doc.cues(at: 3.0).map(\.text) == ["B overlapping A"])
        #expect(doc.cues(at: 12.0).isEmpty)
    }

    @Test("handles an empty document")
    func empty() {
        let empty = SubtitleParser.parse("")
        #expect(empty.isEmpty)
        #expect(empty.cues(at: 5).isEmpty)
    }

    @Test("agrees with a linear scan across a large file")
    func matchesLinearScan() {
        // The lookup is a binary search plus a bounded walk backwards, which is
        // where an off-by-one would hide. Check it against the obvious
        // implementation over a file the size of a feature.
        var text = ""
        for i in 0..<2000 {
            let start = Double(i) * 3
            text += "\(i + 1)\n\(stamp(start)) --> \(stamp(start + 2))\nLine \(i)\n\n"
        }
        let big = SubtitleParser.parse(text)
        #expect(big.cues.count == 2000)

        for probe in stride(from: 0.0, through: 5999.0, by: 7.3) {
            let fast = big.cues(at: probe).map(\.id)
            let slow = big.cues.filter { $0.contains(probe) }.map(\.id)
            #expect(fast == slow, "disagreed at \(probe)")
        }
    }

    private func stamp(_ seconds: Double) -> String {
        let whole = Int(seconds)
        return String(
            format: "%02d:%02d:%02d,%03d",
            whole / 3600, (whole % 3600) / 60, whole % 60,
            Int((seconds - Double(whole)) * 1000)
        )
    }
}
