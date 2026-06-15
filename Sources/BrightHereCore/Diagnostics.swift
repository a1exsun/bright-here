import CoreGraphics
import Foundation

public struct DisplaySnapshot: Equatable, Sendable {
    public let display: ManagedDisplay
    public let brightness: Float?
    public let containsPointer: Bool

    public init(display: ManagedDisplay, brightness: Float?, containsPointer: Bool) {
        self.display = display
        self.brightness = brightness
        self.containsPointer = containsPointer
    }
}

public struct PointerDiagnostics: Equatable, Sendable {
    public let pointerLocation: CGPoint?
    public let selectedDisplay: ManagedDisplay?
    public let displays: [DisplaySnapshot]

    public init(pointerLocation: CGPoint?, selectedDisplay: ManagedDisplay?, displays: [DisplaySnapshot]) {
        self.pointerLocation = pointerLocation
        self.selectedDisplay = selectedDisplay
        self.displays = displays
    }
}

public struct DiagnosticsCollector {
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

    public func snapshot() -> PointerDiagnostics {
        let point = pointerLocator.currentPointerLocation()
        let displays = displayProvider.allKnownDisplays()
        let selected = point.flatMap { displayLocator.display(containing: $0, displays: displays) }
        let snapshots = displays.map { display in
            DisplaySnapshot(
                display: display,
                brightness: brightness.brightness(for: display.id),
                containsPointer: point.map { display.bounds.contains($0) } ?? false
            )
        }

        return PointerDiagnostics(pointerLocation: point, selectedDisplay: selected, displays: snapshots)
    }
}

public enum DiagnosticsFormatter {
    public static func point(_ point: CGPoint?) -> String {
        guard let point else {
            return "n/a"
        }
        return String(format: "%.1f, %.1f", point.x, point.y)
    }

    public static func rect(_ rect: CGRect) -> String {
        String(
            format: "%.0fx%.0f%+.0f%+.0f",
            rect.width,
            rect.height,
            rect.origin.x,
            rect.origin.y
        )
    }

    public static func brightness(_ value: Float?) -> String {
        guard let value else {
            return "n/a"
        }
        return "\(Int((value * 100).rounded()))%"
    }
}
