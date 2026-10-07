import Foundation

public enum AyuDatacenterInfo {
    // Broad, established city labels only; no precise-site claims.
    private static let locations: [Int: String] = [1: "Miami", 2: "Amsterdam", 3: "Miami", 4: "Amsterdam", 5: "Singapore"]

    public static func displayName(for id: Int) -> String {
        self.locations[id].map { "DC\(id) · \($0)" } ?? "DC\(id)"
    }
}
