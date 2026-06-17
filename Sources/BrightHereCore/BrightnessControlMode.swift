import Foundation

public enum BrightnessControlMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case gamma
    case ddcCI = "ddc-ci"
    case overlay

    public var id: String {
        rawValue
    }
}
