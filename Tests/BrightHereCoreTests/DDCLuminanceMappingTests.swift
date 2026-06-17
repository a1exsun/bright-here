import Testing
@testable import BrightHereCore

@Suite("DDC luminance mapping")
struct DDCLuminanceMappingTests {
    @Test("uses full reported range by default")
    func usesFullReportedRangeByDefault() {
        let mapping = DDCBrightnessController.LuminanceMapping(
            reportedMaximum: 100,
            repeatsAtHalfRange: false
        )

        #expect(mapping.rawValue(for: 0) == 0)
        #expect(mapping.rawValue(for: 0.5) == 50)
        #expect(mapping.rawValue(for: 1) == 100)
        #expect(mapping.normalized(current: 50) == 0.5)
        #expect(mapping.normalized(current: 100) == 1)
    }

    @Test("maps repeated half-range displays to one logical range")
    func mapsRepeatedHalfRangeDisplaysToOneLogicalRange() {
        let mapping = DDCBrightnessController.LuminanceMapping(
            reportedMaximum: 100,
            repeatsAtHalfRange: true
        )

        #expect(mapping.rawValue(for: 0) == 0)
        #expect(mapping.rawValue(for: 0.5) == 25)
        #expect(mapping.rawValue(for: 1) == 50)
        #expect(mapping.normalized(current: 0) == 0)
        #expect(mapping.normalized(current: 50) == 1)
        #expect(mapping.normalized(current: 51) == 0.02)
        #expect(mapping.normalized(current: 100) == 1)
    }
}
