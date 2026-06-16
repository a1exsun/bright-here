import Foundation

public enum BrightnessControlMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case ddcCI = "ddc-ci"
    case gamma
    case overlay

    public var id: String {
        rawValue
    }
}
