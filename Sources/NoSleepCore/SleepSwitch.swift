import AppKit
import IOKit

/// The one setting that keeps a Mac running with its lid closed.
///
/// Power assertions — what `caffeinate` and most "stay awake" apps hold — stop
/// idle sleep but not clamshell sleep. Only `pmset disablesleep` does, and only
/// root may change it. So writes go through `sudo -n` against a rule NoSleep
/// installs once, and reads go straight to the IORegistry, which needs nothing.
public enum SleepSwitch {
    public static let rulePath = "/etc/sudoers.d/nosleep"

    public enum Failure: LocalizedError, Equatable {
        /// sudo wanted a password: the rule is missing, or predates a command we now use.
        case needsAccess
        /// The password dialog was dismissed.
        case cancelled
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .needsAccess: "NoSleep needs your password once to switch sleep."
            case .cancelled: "Cancelled."
            case .failed(let message): message
            }
        }
    }

    public static var isSleepDisabled: Bool { rootDomainFlag("SleepDisabled") ?? false }

    /// Only true when closing the lid is what would put this Mac to sleep. With an
    /// external display attached the lid can be shut and the Mac keeps running anyway.
    public static var isLidClosedAndWouldSleep: Bool {
        (rootDomainFlag("AppleClamshellState") ?? false)
            && (rootDomainFlag("AppleClamshellCausesSleep") ?? false)
    }

    public static var hasPasswordFreeAccess: Bool {
        FileManager.default.fileExists(atPath: rulePath)
    }

    /// Never prompts. Throws `.needsAccess` when the rule is not in place yet.
    public static func setSleepDisabled(_ disabled: Bool) throws {
        let result = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"])
        guard result.status != 0 else { return }
        if !hasPasswordFreeAccess || result.output.contains("password") {
            throw Failure.needsAccess
        }
        throw Failure.failed(result.output.isEmpty ? "pmset refused the change." : result.output)
    }

    /// Re-enabling sleep with the lid already shut does not by itself send the Mac
    /// to sleep, so a session that ends in a bag has to ask for it.
    public static func sleepNow() {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "sleepnow"])
    }

    /// With sleep disabled, shutting the lid no longer turns the panel off by
    /// itself. Needs no root.
    public static func displaySleepNow() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    public static var isLowPowerOn: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// Never prompts. Throws `.needsAccess` when the rule predates Low Power Mode.
    public static func setLowPower(_ on: Bool) throws {
        let result = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "lowpowermode", on ? "1" : "0"])
        guard result.status != 0 else { return }
        if result.output.contains("password") || result.output.contains("not allowed") { throw Failure.needsAccess }
        throw Failure.failed(result.output.isEmpty ? "pmset refused Low Power Mode." : result.output)
    }

    /// Whether the installed rule covers every command in `rule(for:)`. Spawns
    /// sudo, so check it at launch and after a change, not on every tick.
    public static var hasCurrentRule: Bool {
        // `sudo -l <command>` says yes to any command an admin may run with a
        // password, so read the NOPASSWD lines of the full listing instead.
        guard hasPasswordFreeAccess else { return false }
        return coversEveryCommand(listing: run("/usr/bin/sudo", ["-n", "-l"]).output)
    }

    static func coversEveryCommand(listing: String) -> Bool {
        let allowed = listing.components(separatedBy: .newlines)
            .filter { $0.contains("NOPASSWD:") }
            .flatMap { $0.components(separatedBy: "NOPASSWD:")[1].components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let needed = rule(for: "").components(separatedBy: "NOPASSWD: ")[1].components(separatedBy: ", ")
        return needed.allSatisfy(allowed.contains)
    }

    /// Asks for the admin password once, writes the sudoers rule, and applies
    /// `disabled` in the same breath so the first switch takes one prompt, not two.
    /// nil writes the rule and changes nothing else. Blocks while the dialog is up.
    public static func installAccess(applying disabled: Bool?) throws {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil else {
            throw Failure.failed("The account name “\(user)” can't go in a sudoers rule as is. See the README to add it by hand.")
        }
        var error: NSDictionary?
        NSAppleScript(source: setupSource(user: user, applying: disabled))?.executeAndReturnError(&error)
        guard let error else { return }
        if error[NSAppleScript.errorNumber] as? Int == -128 { throw Failure.cancelled }
        throw Failure.failed(error[NSAppleScript.errorMessage] as? String ?? "The change was refused.")
    }

    /// Exactly the commands NoSleep runs, with their arguments, and nothing else.
    public static func rule(for user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, "
            + "/usr/bin/pmset sleepnow, /usr/bin/pmset -a lowpowermode 0, /usr/bin/pmset -a lowpowermode 1"
    }

    static func setupSource(user: String, applying disabled: Bool?) -> String {
        """
        do shell script "\(appleScriptEscaped(installScript(user: user, applying: disabled)))" \
        with prompt "NoSleep needs your password once, so it can switch lid-closed sleep from now on." \
        with administrator privileges
        """
    }

    static func installScript(user: String, applying disabled: Bool?) -> String {
        // visudo checks the file before it goes in: a sudoers file that fails to
        // parse breaks sudo for every account on the Mac.
        """
        t=$(/usr/bin/mktemp) || exit 1
        /usr/bin/printf '%s\\n' '# Written by NoSleep.app: lets \(user) switch lid-closed sleep without a password.' '\(rule(for: user))' > "$t"
        /usr/sbin/visudo -cqf "$t" && /usr/bin/install -m 0440 -o root -g wheel "$t" \(rulePath)
        s=$?
        /bin/rm -f "$t"
        [ $s -eq 0 ] || exit $s
        \(disabled.map { "/usr/bin/pmset -a disablesleep \($0 ? 1 : 0)" } ?? "exit 0")
        """
    }

    static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func rootDomainFlag(_ key: String) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? NSNumber)?.boolValue
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output)
    }
}
