import Foundation

/// When an awake session should hand the Mac back to normal sleep.
public struct Limits: Equatable, Sendable {
    /// nil runs until switched off.
    public var until: Date?
    /// nil never stops for the battery.
    public var batteryFloor: Int?

    public init(until: Date? = nil, batteryFloor: Int? = nil) {
        self.until = until
        self.batteryFloor = batteryFloor
    }

    public enum StopReason: Equatable, Sendable {
        case timer
        case battery(Int)
        case heat
    }

    public func reasonToStop(now: Date, power: PowerSource, thermal: ProcessInfo.ThermalState = .nominal) -> StopReason? {
        // Heat first: a Mac that is critically hot stops whatever the timer says.
        if thermal == .critical { return .heat }
        if let until, now >= until { return .timer }
        // Plugged in, the battery is not draining, so the floor has nothing to protect.
        if let batteryFloor, power.onBattery, let percent = power.batteryPercent, percent <= batteryFloor {
            return .battery(percent)
        }
        return nil
    }
}

/// When an awake Mac should run in Low Power Mode. Hardcoded on purpose: these
/// are the defaults Insomnia ships, and nobody has asked to change them.
public enum LowPowerRule {
    public static let batteryBelow = 40

    public enum Reason: Equatable, Sendable {
        case lidClosed
        case battery(Int)
        case heat
    }

    public static func reason(lidClosed: Bool, power: PowerSource, thermal: ProcessInfo.ThermalState) -> Reason? {
        if thermal == .serious || thermal == .critical { return .heat }
        if lidClosed { return .lidClosed }
        if power.onBattery, let percent = power.batteryPercent, percent < batteryBelow { return .battery(percent) }
        return nil
    }
}
