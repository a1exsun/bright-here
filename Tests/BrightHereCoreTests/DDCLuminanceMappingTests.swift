import Testing
@testable import BrightHereCore

@Suite("DDC luminance mapping")
struct DDCLuminanceMappingTests {
    @Test("maps full logical brightness into the first 40 percent of raw DDC luminance")
    func mapsLogicalBrightnessIntoFirstFortyPercent() {
        let mapping = DDCBrightnessController.LuminanceMapping(reportedMaximum: 100)

        #expect(mapping.rawValue(for: 0) == 0)
        #expect(mapping.rawValue(for: 0.5) == 20)
        #expect(mapping.rawValue(for: 1) == 40)
        #expect(mapping.rawMaximum == 40)
        #expect(mapping.rawMaximumPercent == 0.40)
    }

    @Test("clamps raw readback above the mapped DDC ceiling")
    func clampsRawReadbackAboveMappedCeiling() {
        let mapping = DDCBrightnessController.LuminanceMapping(reportedMaximum: 100)

        #expect(mapping.normalized(current: 0) == 0)
        #expect(mapping.normalized(current: 20) == 0.5)
        #expect(mapping.normalized(current: 40) == 1)
        #expect(mapping.normalized(current: 41) == 1)
        #expect(mapping.normalized(current: 100) == 1)
    }

    @Test("does not exceed 40 percent for non-100 reported maximums")
    func doesNotExceedFortyPercentForOtherMaximums() {
        let mapping = DDCBrightnessController.LuminanceMapping(reportedMaximum: 255)

        #expect(mapping.rawMaximum == 102)
        #expect(mapping.rawValue(for: 1) == 102)
        #expect(mapping.rawMaximumPercent <= 0.40)
    }
}
