import Foundation
import LocalAuthentication
import Security

/// Joins an iPhone's Personal Hotspot when the network drops during a session.
///
/// Goes through `networksetup -setairportnetwork` rather than CoreWLAN: CoreWLAN
/// needs Location Services before it will show a network's name, and
/// networksetup joins by name without that. The password lives in the login
/// Keychain. Left empty, macOS uses the password it already keeps for a
/// hotspot this Mac has joined before.
enum Hotspot {
    static let nameKey = "hotspotName"
    private static let service = "dev.intuito.nosleep.hotspot"
    private static let networksetup = "/usr/sbin/networksetup"

    static var name: String? {
        let name = UserDefaults.standard.string(forKey: nameKey)?.trimmingCharacters(in: .whitespaces)
        return name?.isEmpty == false ? name : nil
    }

    static func save(name: String, password: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        if let old = self.name { deletePassword(for: old) }
        UserDefaults.standard.set(name, forKey: nameKey)
        if !name.isEmpty, !password.isEmpty { setPassword(password, for: name) }
    }

    static func remove() {
        if let name { deletePassword(for: name) }
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    static func hasPassword(for name: String) -> Bool { password(for: name) != nil }

    /// Blocks for as long as networksetup takes, several seconds when the
    /// hotspot is out of range. Call it off the main thread.
    static func join(_ name: String) -> Result<Void, JoinError> {
        guard let device = wifiDevice() else { return .failure(.noWiFi) }
        let output = run([networksetup, "-setairportnetwork", device, name] + (password(for: name).map { [$0] } ?? []))
        // networksetup exits 0 either way and says nothing when it worked.
        return output.isEmpty ? .success(()) : .failure(.refused(output))
    }

    enum JoinError: Error {
        case noWiFi
        case refused(String)

        var message: String {
            switch self {
            case .noWiFi: "No Wi-Fi hardware found"
            case .refused(let output): output
            }
        }
    }

    /// The device of the "Wi-Fi" port in `networksetup -listallhardwareports`, usually en0.
    static func wifiDevice(from listing: String? = nil) -> String? {
        let lines = (listing ?? run([networksetup, "-listallhardwareports"])).components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where line.hasPrefix("Hardware Port:") {
            let port = line.dropFirst("Hardware Port:".count).trimmingCharacters(in: .whitespaces)
            guard port == "Wi-Fi" || port == "AirPort", index + 1 < lines.count else { continue }
            let next = lines[index + 1]
            guard next.hasPrefix("Device:") else { continue }
            return next.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - Keychain

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    /// Never prompts: this runs unattended, often with the lid shut. A build
    /// signed ad hoc may lose access to an item saved by an older build, and
    /// then the join goes ahead without it.
    private static func password(for name: String) -> String? {
        var item: CFTypeRef?
        var search = query(name)
        search[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        search[kSecUseAuthenticationContext as String] = context
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func setPassword(_ password: String, for name: String) {
        deletePassword(for: name)
        var item = query(name)
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "NoSleep hotspot: \(name)"
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func deletePassword(for name: String) {
        SecItemDelete(query(name) as CFDictionary)
    }

    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return error.localizedDescription }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
