import Testing
@testable import BrightHereCore

@Suite("Brightness indicator state")
struct BrightnessIndicatorStateTests {
    @Test("clamps values to displayable brightness range")
    func clampsValues() {
        #expect(BrightnessIndicatorState(value: -0.4).normalizedValue == 0)
        #expect(BrightnessIndicatorState(value: 1.4).normalizedValue == 1)
    }

    @Test("rounds brightness percent")
    func roundsPercent() {
        #expect(BrightnessIndicatorState(value: 0.314).percent == 31)
        #expect(BrightnessIndicatorState(value: 0.315).percent == 32)
    }
}
