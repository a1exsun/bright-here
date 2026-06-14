import Foundation

public enum BrightnessDirection: Sendable {
    case up
    case down

    public var multiplier: Float {
        switch self {
        case .up: return 1
        case .down: return -1
        }
    }
}

public struct BrightnessAdjustmentResult: Equatable, Sendable {
    public let oldValue: Float
    public let newValue: Float
}

public struct BrightnessAdjuster: Sendable {
    public let step: Float

    public init(step: Float = 0.0625) {
        self.step = max(0.005, min(step, 0.25))
    }

    public func adjustedValue(current: Float, direction: BrightnessDirection) -> Float {
        let next = current + (step * direction.multiplier)
        return min(max(next, 0), 1)
    }

    public func adjust(
        displayID: DisplayID,
        direction: BrightnessDirection,
        brightness: BrightnessControlling
    ) -> BrightnessAdjustmentResult? {
        guard let current = brightness.brightness(for: displayID) else {
            return nil
        }

        let next = adjustedValue(current: current, direction: direction)
        guard brightness.setBrightness(next, for: displayID) else {
            return nil
        }

        return BrightnessAdjustmentResult(oldValue: current, newValue: next)
    }
}
