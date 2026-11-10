// Ported from MacSlapApp (github.com/AbdullahFID/MacSlapApp).
// Copyright (c) 2026 Abdullah Khan. MIT License; see THIRD-PARTY-NOTICES.md.
// The approach comes from taigrr/spank and olvvier/apple-silicon-accelerometer.

import Foundation
import IOKit
import IOKit.hid

/// The MacBook's accelerometer, read straight from its HID device.
///
/// Apple silicon MacBooks (M1 Pro, M2 and later) carry an IMU behind the
/// `AppleSPUHIDDevice` with vendor usage page `0xFF00`, usage `3`. It is off
/// until its `AppleSPUHIDDriver` is told to report; then it streams 22-byte
/// input reports at about 800 Hz, X, Y and Z as little-endian Q16 int32 at
/// bytes 6, 10 and 14. The device is opened by its registry entry, not through
/// IOHIDManager, and needs no permission.
///
/// `stop()` turns the sensor's reporting and power back off, as nothing else
/// on the Mac uses it. The driver's `ReportInterval` reads 0 even while it
/// streams, so there is no telling whether another app had woken it first;
/// one that had (MacSlapApp) wakes it again when its stream stalls.
public final class Accelerometer: @unchecked Sendable {
    private static let usagePage = 0xFF00
    private static let usage = 3
    /// Microseconds; the hardware clamps it to about 800 Hz.
    private static let interval: Int32 = 1000

    private var session: Session?

    /// Nil on a Mac without the sensor: desktops, Intel MacBooks, the M1 MacBook Air and 13-inch Pro.
    public static func open() -> Accelerometer? {
        guard let service = service(class: "AppleSPUHIDDevice") else { return nil }
        IOObjectRelease(service)
        return Accelerometer()
    }

    private init() {}

    /// Starts streaming; `onSample` is called on the sensor's own thread with
    /// X, Y and Z in g. True if the device opened.
    @discardableResult
    public func start(onSample: @escaping @Sendable (Double, Double, Double) -> Void) -> Bool {
        stop()
        Self.setDriver(reporting: true)
        guard let service = Self.service(class: "AppleSPUHIDDevice") else { return false }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service),
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            Self.setDriver(reporting: false)
            return false
        }
        // Again, now the device is open: on some models the first wake is lost.
        Self.setDriver(reporting: true)
        let session = Session(device: device, onSample: onSample)
        session.start()
        self.session = session
        return true
    }

    public func stop() {
        guard let session else { return }
        session.cancel()
        self.session = nil
        Self.setDriver(reporting: false)
    }

    // MARK: - Registry

    private static func isAccelerometer(_ entry: io_registry_entry_t) -> Bool {
        func number(_ key: String) -> Int? {
            (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
        }
        return number("PrimaryUsagePage") == usagePage && number("PrimaryUsage") == usage
    }

    /// The first accelerometer entry of `class`, retained; the caller releases it.
    private static func service(class name: String) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if isAccelerometer(entry) { return entry }
            IOObjectRelease(entry)
        }
        return nil
    }

    /// Power and reporting live on the driver; set on the HID device they are
    /// silently ignored and the sensor never streams.
    private static func setDriver(reporting: Bool) {
        guard let driver = service(class: "AppleSPUHIDDriver") else { return }
        defer { IOObjectRelease(driver) }
        let on: Int32 = reporting ? 1 : 0
        for (key, value) in [("SensorPropertyReportingState", on), ("SensorPropertyPowerState", on),
                             ("ReportInterval", reporting ? interval : 0)] {
            IORegistryEntrySetCFProperty(driver, key as CFString, NSNumber(value: value))
        }
    }
}

/// One open device, serviced on its own thread: the main run loop stalls
/// while a menu is open, and a slap lasts a few milliseconds. The thread owns
/// the report buffer and frees it only after closing the device, so a late
/// callback can never touch freed memory.
private final class Session: @unchecked Sendable {
    private static let bufferSize = 64

    private let device: IOHIDDevice
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Session.bufferSize)
    private let onSample: @Sendable (Double, Double, Double) -> Void
    private let lock = NSLock()
    private var cancelled = false

    init(device: IOHIDDevice, onSample: @escaping @Sendable (Double, Double, Double) -> Void) {
        self.device = device
        self.onSample = onSample
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func start() {
        let context = Unmanaged.passRetained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.bufferSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            Unmanaged<Session>.fromOpaque(context).takeUnretainedValue().handle(report, length: length)
        }, context)
        let thread = Thread { [device, buffer] in
            let runLoop: CFRunLoop = CFRunLoopGetCurrent()
            IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
            while !self.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.25, true)
            }
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            buffer.deallocate()
            Unmanaged<Session>.fromOpaque(context).release()
        }
        thread.name = "NoSleep accelerometer"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func handle(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard length >= 18 else { return }
        func axis(_ offset: Int) -> Double {
            let raw = UInt32(report[offset]) | UInt32(report[offset + 1]) << 8
                | UInt32(report[offset + 2]) << 16 | UInt32(report[offset + 3]) << 24
            return Double(Int32(bitPattern: raw)) / 65536
        }
        let x = axis(6), y = axis(10), z = axis(14)
        // At rest the sensor reads 1 g; anything far from that is not this layout.
        let magnitude = (x * x + y * y + z * z).squareRoot()
        guard magnitude > 0.2, magnitude < 25 else { return }
        onSample(x, y, z)
    }
}
