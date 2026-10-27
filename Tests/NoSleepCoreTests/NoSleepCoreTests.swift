import AppKit
import Testing
@testable import NoSleepCore

@Suite("When a session stops")
struct LimitsTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let onBattery = PowerSource(batteryPercent: 50, onBattery: true)

    @Test("With no limits a session runs on")
    func noLimits() {
        #expect(Limits().reasonToStop(now: now, power: PowerSource(batteryPercent: 1, onBattery: true)) == nil)
    }

    @Test("A timer stops the session once its time has come, not before")
    func timer() {
        let limits = Limits(until: now)
        #expect(limits.reasonToStop(now: now.addingTimeInterval(-1), power: onBattery) == nil)
        #expect(limits.reasonToStop(now: now, power: onBattery) == .timer)
    }

    @Test("The battery stop fires at the floor, reporting the level it saw")
    func batteryFloor() {
        let limits = Limits(batteryFloor: 20)
        #expect(limits.reasonToStop(now: now, power: PowerSource(batteryPercent: 21, onBattery: true)) == nil)
        #expect(limits.reasonToStop(now: now, power: PowerSource(batteryPercent: 20, onBattery: true)) == .battery(20))
        #expect(limits.reasonToStop(now: now, power: PowerSource(batteryPercent: 7, onBattery: true)) == .battery(7))
    }

    @Test("Plugged in, a low battery does not stop the session")
    func pluggedIn() {
        let limits = Limits(batteryFloor: 20)
        #expect(limits.reasonToStop(now: now, power: PowerSource(batteryPercent: 5, onBattery: false)) == nil)
    }

    @Test("Critical heat stops the session even with time left on the timer")
    func heat() {
        let limits = Limits(until: now.addingTimeInterval(3600))
        #expect(limits.reasonToStop(now: now, power: onBattery, thermal: .serious) == nil)
        #expect(limits.reasonToStop(now: now, power: onBattery, thermal: .critical) == .heat)
    }

    @Test("A Mac without a battery is never stopped by the battery floor")
    func desktop() {
        let limits = Limits(batteryFloor: 50)
        #expect(limits.reasonToStop(now: now, power: PowerSource(batteryPercent: nil, onBattery: false)) == nil)
    }
}

@Suite("When Low Power Mode is wanted")
struct LowPowerTests {
    let plugged = PowerSource(batteryPercent: 90, onBattery: false)

    @Test("Nothing asks for Low Power Mode on a cool, open, plugged-in Mac")
    func idle() {
        #expect(LowPowerRule.reason(lidClosed: false, power: plugged, thermal: .fair) == nil)
    }

    @Test("A closed lid, a battery under 40% or serious heat each ask for it")
    func reasons() {
        #expect(LowPowerRule.reason(lidClosed: true, power: plugged, thermal: .nominal) == .lidClosed)
        #expect(LowPowerRule.reason(lidClosed: false, power: PowerSource(batteryPercent: 39, onBattery: true), thermal: .nominal) == .battery(39))
        #expect(LowPowerRule.reason(lidClosed: false, power: PowerSource(batteryPercent: 40, onBattery: true), thermal: .nominal) == nil)
        #expect(LowPowerRule.reason(lidClosed: true, power: plugged, thermal: .serious) == .heat)
    }

    @Test("A low battery doesn't ask for it while charging")
    func charging() {
        #expect(LowPowerRule.reason(lidClosed: false, power: PowerSource(batteryPercent: 10, onBattery: false), thermal: .nominal) == nil)
    }
}

@Suite("The sudoers rule")
struct RuleTests {
    @Test("The rule allows exactly the pmset commands NoSleep runs")
    func ruleIsNarrow() {
        let rule = SleepSwitch.rule(for: "someone")
        let commands = rule.components(separatedBy: "NOPASSWD: ")[1].components(separatedBy: ", ")
        #expect(rule.hasPrefix("someone ALL=(root) NOPASSWD: "))
        #expect(commands == [
            "/usr/bin/pmset -a disablesleep 0",
            "/usr/bin/pmset -a disablesleep 1",
            "/usr/bin/pmset sleepnow",
            "/usr/bin/pmset -a lowpowermode 0",
            "/usr/bin/pmset -a lowpowermode 1",
        ])
    }

    @Test("The rule is valid sudoers syntax, because a broken one would lock everyone out of sudo")
    func ruleParses() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nosleep-rule-\(UUID().uuidString)")
        try (SleepSwitch.rule(for: NSUserName()) + "\n").write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let visudo = Process()
        visudo.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
        visudo.arguments = ["-cqf", file.path]
        try visudo.run()
        visudo.waitUntilExit()
        #expect(visudo.terminationStatus == 0)
    }

    @Test("The install script survives the trip through an AppleScript string literal")
    func escaping() {
        let script = SleepSwitch.installScript(user: "someone", applying: true)
        let escaped = SleepSwitch.appleScriptEscaped(script)
        #expect(!escaped.contains("\n"))
        // Undo the escaping the way AppleScript reads it back.
        var decoded = ""
        var iterator = escaped.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else { decoded.append(character); continue }
            decoded.append(next == "n" ? "\n" : next)
        }
        #expect(decoded == script)
    }

    @Test("A rule from before Low Power Mode reads as out of date, even for an admin who may sudo anything")
    func staleRule() {
        let old = """
            User someone may run the following commands on mac:
                (ALL) ALL
                (root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset sleepnow
            """
        #expect(!SleepSwitch.coversEveryCommand(listing: old))
        let current = "    (root) NOPASSWD: " + SleepSwitch.rule(for: "someone").components(separatedBy: "NOPASSWD: ")[1]
        #expect(SleepSwitch.coversEveryCommand(listing: current))
    }

    @Test("Updating the rule alone writes it and leaves sleep as it is")
    func ruleOnly() {
        let script = SleepSwitch.installScript(user: "someone", applying: nil)
        #expect(!script.contains("disablesleep 1\n") && script.hasSuffix("exit 0"))
    }

    @Test("The password dialog's AppleScript compiles, so the first switch cannot fail on a syntax slip")
    func setupCompiles() throws {
        // Compiling never runs it, so no dialog appears.
        var error: NSDictionary?
        let script = try #require(NSAppleScript(source: SleepSwitch.setupSource(user: "someone", applying: true)))
        let compiled = script.compileAndReturnError(&error)
        #expect(compiled, "\(error ?? [:])")
    }
}
