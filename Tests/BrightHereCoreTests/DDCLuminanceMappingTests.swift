import Testing
@testable import BrightHereCore

@Suite("DDC luminance mapping")
struct DDCLuminanceMappingTests {
    @Test("maps full logical brightness into the first 38 percent of raw DDC luminance")
    func mapsLogicalBrightnessIntoFirstThirtyEightPercent() {
        let mapping = DDCBrightnessController.LuminanceMapping(reportedMaximum: 100)

        #expect(mapping.rawValue(for: 0) == 0)
        #expect(mapping.rawValue(for: 0.5) == 19)
        #expect(mapping.rawValue(for: 1) == 38)
        #expect(mapping.rawMaximum == 38)
        #expect(mapping.rawMaximumPercent == 0.38)
    }

    @Test("clamps raw readback above the mapped DDC ceiling")
    func clampsRawReadbackAboveMappedCeiling() {
        let mapping = DDCBrightnessController.LuminanceMapping(reportedMaximum: 100)

        #expect(mapping.normalized(current: 0) == 0)
        #expect(mapping.normalized(current: 19) == 0.5)
        #expect(mapping.normalized(current: 38) == 1)
        #expect(mapping.normalized(current: 39) == 1)
        #expect(mapping.normalized(current: 100) == 1)
    }

    @Test("does not exceed 38 percent for non-100 reported maximums")
    func doesNotExceedThirtyEightPercentForOtherMaximums() {
        let mapping = DDCBrightnessController.LuminanceMapping(reportedMaximum: 255)

        #expect(mapping.rawMaximum == 96)
        #expect(mapping.rawValue(for: 1) == 96)
        #expect(mapping.rawMaximumPercent <= 0.38)
    }
}
