import CoreGraphics
import Testing
@testable import BrightHereCore

@Suite("Display locator")
struct DisplayLocatorTests {
    @Test("selects display containing pointer")
    func selectsContainingDisplay() {
        let displays = [
            display(id: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            display(id: 2, bounds: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]

        let result = DisplayLocator().display(containing: CGPoint(x: 140, y: 40), displays: displays)

        #expect(result?.id == 2)
    }

    @Test("falls back to nearest online active display")
    func selectsNearestDisplay() {
        let displays = [
            display(id: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            display(id: 2, bounds: CGRect(x: 300, y: 0, width: 100, height: 100))
        ]

        let result = DisplayLocator().display(containing: CGPoint(x: 220, y: 40), displays: displays)

        #expect(result?.id == 2)
    }

    @Test("ignores inactive displays")
    func ignoresInactiveDisplay() {
        let displays = [
            display(id: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), isActive: false),
            display(id: 2, bounds: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]

        let result = DisplayLocator().display(containing: CGPoint(x: 40, y: 40), displays: displays)

        #expect(result?.id == 2)
    }
}

private func display(
    id: DisplayID,
    bounds: CGRect,
    isActive: Bool = true,
    isOnline: Bool = true
) -> ManagedDisplay {
    ManagedDisplay(
        index: Int(id),
        id: id,
        bounds: bounds,
        isMain: id == 1,
        isBuiltin: false,
        isActive: isActive,
        isOnline: isOnline,
        isAsleep: false,
        source: "test"
    )
}
