import Testing
@testable import MediaHubKit

@Suite("Ticks")
struct TicksTests {
    @Test("converts to and from seconds")
    func roundTrip() {
        #expect(Ticks(seconds: 1).rawValue == 10_000_000)
        #expect(Ticks(rawValue: 10_000_000).seconds == 1)
        #expect(Ticks(seconds: 90.5).rawValue == 905_000_000)
    }

    @Test("refuses to represent a negative position")
    func clampsNegatives() {
        // A player reporting a negative time is a bug somewhere upstream, but
        // storing it would turn into a seek to a position that does not exist.
        #expect(Ticks(seconds: -10) == .zero)
        #expect(Ticks(rawValue: -1) == .zero)
    }

    @Test("survives a non-finite seek position")
    func handlesNaN() {
        // AVPlayer reports NaN for currentTime before an item is ready, and
        // that value reaches this initialiser on the way to the progress call.
        #expect(Ticks(seconds: .nan) == .zero)
        #expect(Ticks(seconds: .infinity) == .zero)
    }

    @Test("formats a timecode without a leading zero hour")
    func timecode() {
        #expect(Ticks(seconds: 249).timecode == "4:09")
        #expect(Ticks(seconds: 6127).timecode == "1:42:07")
        #expect(Ticks(seconds: 0).timecode == "0:00")
        #expect(Ticks(seconds: 59.9).timecode == "0:59")
    }
}

@Suite("Resume")
struct ResumeTests {
    private let ninetyMinutes = Runtime(minutes: 90)

    @Test("ignores a position too short to be a viewing")
    func ignoresMisTaps() {
        #expect(Resume.startingPoint(position: Ticks(seconds: 12), runtime: ninetyMinutes) == .zero)
        #expect(Resume.startingPoint(position: Ticks(seconds: 29.9), runtime: ninetyMinutes) == .zero)
    }

    @Test("resumes a real position")
    func resumesRealPositions() {
        let halfway = Ticks(seconds: 2700)
        #expect(Resume.startingPoint(position: halfway, runtime: ninetyMinutes) == halfway)
    }

    @Test("treats the closing credits as finished")
    func restartsNearTheEnd() {
        // 96% through a 90 minute film: the viewer wants to watch it again, not
        // to sit through the last three minutes.
        let credits = Ticks(seconds: 90 * 60 * 0.96)
        #expect(Resume.startingPoint(position: credits, runtime: ninetyMinutes) == .zero)
    }

    @Test("falls back to the floor when the runtime is unknown")
    func noRuntime() {
        // Plenty of files have no metadata match, so runtime is genuinely
        // absent — the percentage rule cannot apply, but the floor still can.
        let position = Ticks(seconds: 600)
        #expect(Resume.startingPoint(position: position, runtime: nil) == position)
        #expect(Resume.startingPoint(position: Ticks(seconds: 5), runtime: nil) == .zero)
    }

    @Test("does not divide by a zero runtime")
    func zeroRuntime() {
        let position = Ticks(seconds: 600)
        #expect(Resume.startingPoint(position: position, runtime: Runtime(seconds: 0)) == position)
    }

    @Test("in-progress agrees with the starting point")
    func inProgress() {
        #expect(Resume.isInProgress(position: Ticks(seconds: 600), runtime: ninetyMinutes))
        #expect(!Resume.isInProgress(position: Ticks(seconds: 3), runtime: ninetyMinutes))
        #expect(!Resume.isInProgress(position: .zero, runtime: ninetyMinutes))
    }
}
