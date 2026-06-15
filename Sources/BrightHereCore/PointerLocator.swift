import CoreGraphics

public protocol PointerLocating {
    func currentPointerLocation() -> CGPoint?
}

public struct CoreGraphicsPointerLocator: PointerLocating {
    public init() {}

    public func currentPointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }
}
