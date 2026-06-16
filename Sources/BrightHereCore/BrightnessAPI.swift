import CoreGraphics
import Darwin
import Foundation

public protocol BrightnessControlling {
    func brightness(for displayID: DisplayID) -> Float?
    @discardableResult
    func setBrightness(_ brightness: Float, for displayID: DisplayID) -> Bool
}

public protocol BrightnessControlResetting {
    func reset()
}

public final class NativeBrightnessController: BrightnessControlling {
    private typealias DSGet = @convention(c) (DisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSet = @convention(c) (DisplayID, Float) -> Int32
    private typealias CDGet = @convention(c) (DisplayID) -> Double
    private typealias CDSet = @convention(c) (DisplayID, Double) -> Void

    private let displayServices: UnsafeMutableRawPointer?
    private let coreDisplay: UnsafeMutableRawPointer?
    private let dsGet: DSGet?
    private let dsSet: DSSet?
    private let cdGet: CDGet?
    private let cdSet: CDSet?

    public init() {
        displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

        dsGet = Self.load(displayServices, "DisplayServicesGetBrightness", as: DSGet.self)
        dsSet = Self.load(displayServices, "DisplayServicesSetBrightness", as: DSSet.self)
        cdGet = Self.load(coreDisplay, "CoreDisplay_Display_GetUserBrightness", as: CDGet.self)
        cdSet = Self.load(coreDisplay, "CoreDisplay_Display_SetUserBrightness", as: CDSet.self)
    }

    deinit {
        if let displayServices { dlclose(displayServices) }
        if let coreDisplay { dlclose(coreDisplay) }
    }

    public var backendSummary: String {
        let ds = "DisplayServices get:\(dsGet != nil ? "yes" : "no") set:\(dsSet != nil ? "yes" : "no")"
        let cd = "CoreDisplay get:\(cdGet != nil ? "yes" : "no") set:\(cdSet != nil ? "yes" : "no")"
        return "\(ds); \(cd)"
    }

    public func brightness(for displayID: DisplayID) -> Float? {
        if let dsGet {
            var value: Float = -1
            if dsGet(displayID, &value) == 0, value >= 0, value <= 1 {
                return value
            }
        }

        if let cdGet {
            let value = cdGet(displayID)
            if value.isFinite, value >= 0, value <= 1 {
                return Float(value)
            }
        }

        return nil
    }

    @discardableResult
    public func setBrightness(_ brightness: Float, for displayID: DisplayID) -> Bool {
        let value = min(max(brightness, 0), 1)

        if let dsSet, dsSet(displayID, value) == 0 {
            return true
        }

        if let cdSet {
            cdSet(displayID, Double(value))
            return true
        }

        return false
    }

    public func canControl(displayID: DisplayID) -> Bool {
        guard CGDisplayIsBuiltin(displayID) != 0 else {
            return false
        }

        return brightness(for: displayID) != nil && (dsSet != nil || cdSet != nil)
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer?, _ symbol: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }
}
