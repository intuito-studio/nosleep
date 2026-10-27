import Foundation

/// What happened during recent sessions, shown in the panel so the morning
/// after can be read back: when the lid closed, what was switched, what undid it.
///
/// Kept in the app's defaults, because the backstop (a separate process) writes
/// to it too.
struct SessionEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var at: Date
    var title: String
    /// What changed, already worded for the panel: "display off · audio muted".
    var detail: String = ""
}

enum SessionLog {
    static let key = "log"
    static let limit = 30

    static func load(_ defaults: UserDefaults = .standard) -> [SessionEvent] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SessionEvent].self, from: data)) ?? []
    }

    @discardableResult
    static func append(_ event: SessionEvent, _ defaults: UserDefaults = .standard) -> [SessionEvent] {
        let events = Array((load(defaults) + [event]).suffix(limit))
        if let data = try? JSONEncoder().encode(events) { defaults.set(data, forKey: key) }
        return events
    }
}

/// The keys the app and the backstop share. A rename here strands whatever an
/// older build left on disk, so don't.
enum StateKey {
    static let ownsSession = "ownsSession"
    static let until = "until"
    static let lowPowerOwned = "lowPowerOwned"
    static let mutedByUs = "mutedByUs"
}
