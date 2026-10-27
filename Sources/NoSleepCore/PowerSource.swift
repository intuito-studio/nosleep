import IOKit.ps

public struct PowerSource: Equatable, Sendable {
    /// nil on a Mac without a battery.
    public var batteryPercent: Int?
    public var onBattery: Bool

    public init(batteryPercent: Int?, onBattery: Bool) {
        self.batteryPercent = batteryPercent
        self.onBattery = onBattery
    }

    public static var current: PowerSource {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let onBattery = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String == kIOPSBatteryPowerValue
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return PowerSource(batteryPercent: current * 100 / max, onBattery: onBattery)
        }
        return PowerSource(batteryPercent: nil, onBattery: false)
    }
}
