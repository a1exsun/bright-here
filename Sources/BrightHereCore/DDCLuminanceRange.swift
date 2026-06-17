import Foundation

public enum DDCLuminanceRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case firstHalf = "first-half"
    case secondHalf = "second-half"

    public var id: String {
        rawValue
    }
}
