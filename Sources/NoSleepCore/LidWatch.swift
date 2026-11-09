import Foundation

/// Whether the Mac really stayed awake while its lid was shut. Users can't
/// see a closed laptop, so the answer is given when the lid opens: awake the
/// whole time, or asleep from when, and why if NoSleep stopped the session.
///
/// Sleep is taken from macOS's own will-sleep notice, not inferred, so a
/// screen that only went dark never counts as sleep.
public struct LidWatch: Sendable {
    public struct Report: Equatable, Sendable {
        public let closedAt: Date
        public let openedAt: Date
        /// The first time the Mac went to sleep with the lid shut, if it did.
        public let sleptAt: Date?
        /// Why NoSleep ended the session with the lid shut, if it did.
        public let stop: Limits.StopReason?

        public init(closedAt: Date, openedAt: Date, sleptAt: Date?, stop: Limits.StopReason?) {
            self.closedAt = closedAt
            self.openedAt = openedAt
            self.sleptAt = sleptAt
            self.stop = stop
        }

        public var stayedAwake: Bool { sleptAt == nil }
        public var shut: TimeInterval { openedAt.timeIntervalSince(closedAt) }
        /// How long it ran with the lid shut before it slept, or all of it.
        public var awake: TimeInterval { (sleptAt ?? openedAt).timeIntervalSince(closedAt) }
    }

    private var closedAt: Date?
    private var sleptAt: Date?
    private var stop: Limits.StopReason?

    public init() {}

    public var isWatching: Bool { closedAt != nil }

    /// Only a lid shut during a session is watched: with NoSleep off, sleep is
    /// what is meant to happen.
    public mutating func lidClosed(at date: Date) {
        closedAt = date
        sleptAt = nil
        stop = nil
    }

    public mutating func stopped(_ reason: Limits.StopReason, at date: Date) {
        guard closedAt != nil, sleptAt == nil, stop == nil else { return }
        stop = reason
    }

    public mutating func willSleep(at date: Date) {
        guard closedAt != nil, sleptAt == nil else { return }
        sleptAt = date
    }

    /// The report for the lid that just opened, nil if none was being watched.
    public mutating func lidOpened(at date: Date) -> Report? {
        guard let closedAt else { return nil }
        let report = Report(closedAt: closedAt, openedAt: date, sleptAt: sleptAt, stop: stop)
        self.closedAt = nil
        sleptAt = nil
        stop = nil
        return report
    }
}
