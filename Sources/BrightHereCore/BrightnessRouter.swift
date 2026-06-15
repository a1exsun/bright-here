import CoreGraphics

public struct BrightnessRoutingResult: Equatable, Sendable {
    public let pointerLocation: CGPoint
    public let display: ManagedDisplay
    public let adjustment: BrightnessAdjustmentResult
}

public struct BrightnessRouter {
    private let displayProvider: DisplayProviding
    private let pointerLocator: PointerLocating
    private let displayLocator: DisplayLocator
    private let brightness: BrightnessControlling

    public init(
        displayProvider: DisplayProviding,
        pointerLocator: PointerLocating,
        displayLocator: DisplayLocator = DisplayLocator(),
        brightness: BrightnessControlling
    ) {
        self.displayProvider = displayProvider
        self.pointerLocator = pointerLocator
        self.displayLocator = displayLocator
        self.brightness = brightness
    }

    public func route(direction: BrightnessDirection, step: Float) -> BrightnessRoutingResult? {
        guard let point = pointerLocator.currentPointerLocation() else {
            return nil
        }

        let displays = displayProvider.allKnownDisplays()
        guard let display = displayLocator.display(containing: point, displays: displays) else {
            return nil
        }

        guard let adjustment = BrightnessAdjuster(step: step).adjust(
            displayID: display.id,
            direction: direction,
            brightness: brightness
        ) else {
            return nil
        }

        return BrightnessRoutingResult(pointerLocation: point, display: display, adjustment: adjustment)
    }
}
