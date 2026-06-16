import Foundation

public struct BrightnessIndicatorState: Equatable, Sendable {
    public let normalizedValue: Float

    public init(value: Float) {
        normalizedValue = min(max(value, 0), 1)
    }

    public var percent: Int {
        Int((normalizedValue * 100).rounded())
    }
}
