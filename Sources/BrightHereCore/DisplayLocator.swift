import CoreGraphics

public struct DisplayLocator: Sendable {
    public init() {}

    public func display(containing point: CGPoint, displays: [ManagedDisplay]) -> ManagedDisplay? {
        let candidates = displays.filter { display in
            display.isOnline && display.isActive && !display.isAsleep
        }

        if let exact = candidates.first(where: { $0.bounds.contains(point) }) {
            return exact
        }

        return nearestDisplay(to: point, displays: candidates)
    }

    private func nearestDisplay(to point: CGPoint, displays: [ManagedDisplay]) -> ManagedDisplay? {
        displays.min { lhs, rhs in
            distanceSquared(from: point, to: lhs.bounds) < distanceSquared(from: point, to: rhs.bounds)
        }
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }
}
