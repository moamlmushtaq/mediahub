import Foundation

/// Positions on the timeline.
///
/// The server speaks in **ticks** — hundred-nanosecond units, 10,000,000 to the
/// second. That is Jellyfin's convention, and it outlived Jellyfin here because
/// the web player, the phone and the database all already agreed on it; changing
/// the unit would have meant changing all three at once to gain nothing.
///
/// This type exists so the rest of the app never handles the raw integer. A
/// bare `Int` called `position` is exactly the sort of thing that gets divided
/// by a thousand somewhere and produces a resume point four hours into a
/// ninety-minute film.
public struct Ticks: Hashable, Sendable, Codable {
    /// Hundred-nanosecond units in one second.
    public static let perSecond = 10_000_000

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = max(0, rawValue)
    }

    public init(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else {
            self.rawValue = 0
            return
        }
        self.rawValue = Int((seconds * Double(Self.perSecond)).rounded())
    }

    public var seconds: Double {
        Double(rawValue) / Double(Self.perSecond)
    }

    public static let zero = Ticks(rawValue: 0)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How a position on the timeline is turned into an offer to continue.
///
/// Two thresholds, and both are about not being annoying rather than about
/// arithmetic:
///
/// * Under half a minute is not a viewing, it is a mis-tap. Offering to resume
///   it makes the app look like it is keeping score of nothing.
/// * Past 95% the credits are rolling. Someone returning to a title there wants
///   to watch it again, not to sit through the last four minutes — so it counts
///   as finished and playback starts from the beginning.
public enum Resume: Sendable {
    public static let minimumSeconds: Double = 30
    public static let finishedFraction: Double = 0.95

    /// Where playback should begin, given what the server remembers.
    ///
    /// - Parameters:
    ///   - position: The stored position.
    ///   - runtime: Total runtime, when known. Without it the percentage rule
    ///     cannot be applied and only the floor is enforced.
    /// - Returns: The offset to start at; `.zero` to start from the beginning.
    public static func startingPoint(position: Ticks, runtime: Runtime?) -> Ticks {
        guard position.seconds >= minimumSeconds else { return .zero }

        if let runtime, runtime.seconds > 0 {
            let fraction = position.seconds / runtime.seconds
            if fraction >= finishedFraction { return .zero }
        }
        return position
    }

    /// Whether a "continue watching" row should carry this item at all.
    public static func isInProgress(position: Ticks, runtime: Runtime?) -> Bool {
        startingPoint(position: position, runtime: runtime).rawValue > 0
    }
}

/// A title's length.
///
/// Named `Runtime` and not `Duration` on purpose: the standard library owns
/// that name now, and a type in this module shadowing it would make every
/// `Duration` at the call site ambiguous for anyone importing MediaHubKit.
public struct Runtime: Hashable, Sendable {
    public let seconds: Double

    public init(seconds: Double) {
        self.seconds = max(0, seconds)
    }

    public init(minutes: Int) {
        self.init(seconds: Double(minutes) * 60)
    }
}

extension Ticks {
    /// `1:42:07`, or `4:09` for anything under an hour.
    ///
    /// Hours are omitted rather than shown as `0:04:09` because a timecode is
    /// read at a glance, and a leading zero-hour is noise on the great majority
    /// of episodes.
    public var timecode: String {
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
