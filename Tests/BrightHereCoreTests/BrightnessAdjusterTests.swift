import Testing
@testable import BrightHereCore

@Suite("Brightness adjuster")
struct BrightnessAdjusterTests {
    @Test("clamps upper bound")
    func clampsUpperBound() {
        let adjuster = BrightnessAdjuster(step: 0.1)
        #expect(adjuster.adjustedValue(current: 0.96, direction: .up) == 1.0)
    }

    @Test("clamps lower bound")
    func clampsLowerBound() {
        let adjuster = BrightnessAdjuster(step: 0.1)
        #expect(adjuster.adjustedValue(current: 0.04, direction: .down) == 0.0)
    }

    @Test("writes adjusted value through controller")
    func writesAdjustedValue() {
        let controller = FakeBrightnessController(values: [7: 0.5])
        let result = BrightnessAdjuster(step: 0.125).adjust(displayID: 7, direction: .up, brightness: controller)

        #expect(result == BrightnessAdjustmentResult(oldValue: 0.5, newValue: 0.625))
        #expect(controller.values[7] == 0.625)
    }
}

private final class FakeBrightnessController: BrightnessControlling {
    var values: [DisplayID: Float]

    init(values: [DisplayID: Float]) {
        self.values = values
    }

    func brightness(for displayID: DisplayID) -> Float? {
        values[displayID]
    }

    func setBrightness(_ brightness: Float, for displayID: DisplayID) -> Bool {
        values[displayID] = brightness
        return true
    }
}
