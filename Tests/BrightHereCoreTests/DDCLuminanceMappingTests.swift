import Testing
@testable import BrightHereCore

@Suite("DDC luminance mapping")
struct DDCLuminanceMappingTests {
    @Test("uses full reported range by default")
    func usesFullReportedRangeByDefault() {
        let mapping = DDCBrightnessController.LuminanceMapping(
            reportedMaximum: 100,
            range: .full
        )

        #expect(mapping.rawValue(for: 0) == 0)
        #expect(mapping.rawValue(for: 0.5) == 50)
        #expect(mapping.rawValue(for: 1) == 100)
        #expect(mapping.normalized(current: 50) == 0.5)
        #expect(mapping.normalized(current: 100) == 1)
    }

    @Test("maps first half range to one logical range")
    func mapsFirstHalfRangeToOneLogicalRange() {
        let mapping = DDCBrightnessController.LuminanceMapping(
            reportedMaximum: 100,
            range: .firstHalf
        )

        #expect(mapping.rawValue(for: 0) == 0)
        #expect(mapping.rawValue(for: 0.5) == 25)
        #expect(mapping.rawValue(for: 1) == 50)
        #expect(mapping.normalized(current: 0) == 0)
        #expect(mapping.normalized(current: 50) == 1)
        #expect(mapping.normalized(current: 51) == 0)
        #expect(mapping.normalized(current: 100) == 1)
    }

    @Test("maps second half range to one logical range")
    func mapsSecondHalfRangeToOneLogicalRange() {
        let mapping = DDCBrightnessController.LuminanceMapping(
            reportedMaximum: 100,
            range: .secondHalf
        )

        #expect(mapping.rawValue(for: 0) == 51)
        #expect(mapping.rawValue(for: 0.5) == 76)
        #expect(mapping.rawValue(for: 1) == 100)
        #expect(mapping.normalized(current: 0) == 0)
        #expect(mapping.normalized(current: 50) == 1)
        #expect(mapping.normalized(current: 51) == 0)
        #expect(mapping.normalized(current: 100) == 1)
    }
}
