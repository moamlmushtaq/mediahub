import Foundation

/// Windows-1256, the Arabic code page, decoded from a table rather than from
/// the platform.
///
/// WHY NOT `String(data:encoding:)`
/// ===============================
/// Because that encoding does not exist on both platforms. `String.Encoding`
/// has `.windowsCP1250` through `.windowsCP1254` and stops; Arabic is reachable
/// on Apple systems only through CoreFoundation's `CFStringEncodings.windowsArabic`,
/// and on Linux `swift-corelibs-foundation` does not carry it at all.
///
/// Using it would mean subtitle decoding that cannot be tested where this
/// project is developed, and that behaves differently on the machine it was
/// tested on than on the machine it ships to. A 128-entry table removes the
/// platform from the question entirely: the same bytes produce the same string
/// everywhere, and the tests prove it here.
///
/// This matters because most Arabic subtitles in this library are Windows-1256.
/// Getting it wrong does not throw — it renders a row of replacement characters
/// where the dialogue should be.
enum WindowsArabic {
    /// Unicode scalars for bytes 0x80…0xFF. Below 0x80 the code page is ASCII.
    ///
    /// Note the entries that are not letters: 0x9D and 0x9E are the zero-width
    /// non-joiner and joiner, and 0xFD/0xFE are the directional marks. They
    /// carry no shape but they change how the text around them is laid out, so
    /// dropping them would quietly alter the rendering of some lines.
    private static let upperHalf: [UInt32] = [
        0x20AC, 0x067E, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,  // 80
        0x02C6, 0x2030, 0x0679, 0x2039, 0x0152, 0x0686, 0x0698, 0x0688,  // 88
        0x06AF, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,  // 90
        0x06A9, 0x2122, 0x0691, 0x203A, 0x0153, 0x200C, 0x200D, 0x06BA,  // 98
        0x00A0, 0x060C, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,  // A0
        0x00A8, 0x00A9, 0x06BE, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,  // A8
        0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,  // B0
        0x00B8, 0x00B9, 0x061B, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x061F,  // B8
        0x06C1, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627,  // C0
        0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F,  // C8
        0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x00D7,  // D0
        0x0637, 0x0638, 0x0639, 0x063A, 0x0640, 0x0641, 0x0642, 0x0643,  // D8
        0x00E0, 0x0644, 0x00E2, 0x0645, 0x0646, 0x0647, 0x0648, 0x00E7,  // E0
        0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x0649, 0x064A, 0x00EE, 0x00EF,  // E8
        0x064B, 0x064C, 0x064D, 0x064E, 0x00F4, 0x064F, 0x0650, 0x00F7,  // F0
        0x0651, 0x00F9, 0x0652, 0x00FB, 0x00FC, 0x200E, 0x200F, 0x06D2,  // F8
    ]

    /// Cannot fail: every one of the 256 byte values has a mapping.
    static func decode(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(data.count)

        for byte in data {
            if byte < 0x80 {
                scalars.append(Unicode.Scalar(byte))
            } else {
                let value = upperHalf[Int(byte) - 0x80]
                // The table is exhaustive and every entry is a valid scalar, so
                // this is total — but a force unwrap here would be a crash in a
                // subtitle parser, and no subtitle is worth that.
                scalars.append(Unicode.Scalar(value) ?? Unicode.Scalar(0xFFFD)!)
            }
        }

        return String(scalars)
    }
}
