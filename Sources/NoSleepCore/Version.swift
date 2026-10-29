/// Release versions as the tags write them: "1.2.0", or "v1.2.0".
public enum Version {
    /// Compares part by part as numbers, so 1.10 is newer than 1.9, and a
    /// missing part counts as 0, so 1.2 and 1.2.0 are the same release.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
}
