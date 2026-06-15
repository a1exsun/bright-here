import CoreGraphics
import Testing
@testable import BrightHereCore

@Suite("Brightness router")
struct BrightnessRouterTests {
    @Test("routes brightness to display containing pointer")
    func routesToPointerDisplay() {
        let displays = [
            testDisplay(id: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            testDisplay(id: 2, bounds: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]
        let brightness = MutableBrightnessController(values: [1: 0.5, 2: 0.5])
        let router = BrightnessRouter(
            displayProvider: StaticDisplayProvider(displays: displays),
            pointerLocator: StaticPointerLocator(point: CGPoint(x: 150, y: 50)),
            brightness: brightness
        )

        let result = router.route(direction: .up, step: 0.1)

        #expect(result?.display.id == 2)
        #expect(brightness.values[1] == 0.5)
        #expect(brightness.values[2] == 0.6)
    }
}

private struct StaticDisplayProvider: DisplayProviding {
    let displays: [ManagedDisplay]

    func allKnownDisplays() -> [ManagedDisplay] {
        displays
    }
}

private struct StaticPointerLocator: PointerLocating {
    let point: CGPoint?

    func currentPointerLocation() -> CGPoint? {
        point
    }
}

private final class MutableBrightnessController: BrightnessControlling {
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

private func testDisplay(id: DisplayID, bounds: CGRect) -> ManagedDisplay {
    ManagedDisplay(
        index: Int(id),
        id: id,
        bounds: bounds,
        isMain: id == 1,
        isBuiltin: false,
        isActive: true,
        isOnline: true,
        isAsleep: false,
        source: "test"
    )
}
