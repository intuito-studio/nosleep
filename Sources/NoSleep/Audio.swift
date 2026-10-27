import AppKit

/// The output mute, through Standard Additions run in-process: no Automation
/// permission, and it follows whichever output is current.
enum Audio {
    static var isMuted: Bool? {
        var error: NSDictionary?
        let result = NSAppleScript(source: "output muted of (get volume settings)")?.executeAndReturnError(&error)
        guard error == nil, let result, result.descriptorType == typeTrue || result.descriptorType == typeFalse
            || result.descriptorType == typeBoolean else { return nil }
        return result.booleanValue
    }

    static func setMuted(_ muted: Bool) {
        var error: NSDictionary?
        NSAppleScript(source: "set volume \(muted ? "with" : "without") output muted")?.executeAndReturnError(&error)
    }
}
