import Foundation

public enum BrightnessKeyEvent: Equatable, Sendable {
    case brightnessUp
    case brightnessDown
}

public struct SystemDefinedEventDecoder: Sendable {
    public static let auxControlButtonSubtype = 8
    public static let keyDownState = 0x0A
    public static let brightnessDownKeyType = 2
    public static let brightnessUpKeyType = 3

    public init() {}

    public func decode(subtype: Int, data1: Int) -> BrightnessKeyEvent? {
        guard subtype == Self.auxControlButtonSubtype else {
            return nil
        }

        let keyType = (data1 & 0xFFFF0000) >> 16
        let keyState = (data1 & 0x0000FF00) >> 8
        guard keyState == Self.keyDownState else {
            return nil
        }

        switch keyType {
        case Self.brightnessDownKeyType:
            return .brightnessDown
        case Self.brightnessUpKeyType:
            return .brightnessUp
        default:
            return nil
        }
    }
}
