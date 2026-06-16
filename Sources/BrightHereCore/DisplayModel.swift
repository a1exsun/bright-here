import CoreGraphics
import Foundation

public typealias DisplayID = CGDirectDisplayID

public struct ManagedDisplay: Identifiable, Equatable, Sendable {
    public let index: Int
    public let id: DisplayID
    public let bounds: CGRect
    public let isMain: Bool
    public let isBuiltin: Bool
    public let isActive: Bool
    public let isOnline: Bool
    public let isAsleep: Bool
    public let source: String
    public let displayName: String?

    public init(
        index: Int,
        id: DisplayID,
        bounds: CGRect,
        isMain: Bool,
        isBuiltin: Bool,
        isActive: Bool,
        isOnline: Bool,
        isAsleep: Bool,
        source: String,
        displayName: String? = nil
    ) {
        self.index = index
        self.id = id
        self.bounds = bounds
        self.isMain = isMain
        self.isBuiltin = isBuiltin
        self.isActive = isActive
        self.isOnline = isOnline
        self.isAsleep = isAsleep
        self.source = source
        self.displayName = displayName
    }

    public var roleDescription: String {
        var tags: [String] = []
        if isMain { tags.append("main") }
        if isBuiltin { tags.append("built-in") }
        if isActive { tags.append("active") }
        if isOnline { tags.append("online") }
        if isAsleep { tags.append("asleep") }
        return tags.isEmpty ? "" : tags.joined(separator: ", ")
    }

    public var friendlyName: String {
        if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            return displayName
        }
        if isBuiltin {
            return "Built-in Liquid Retina XDR Display"
        }
        if isMain {
            return "Main External Display"
        }
        return "Display #\(index)"
    }

    public var settingsIdentity: String {
        let vendor = CGDisplayVendorNumber(id)
        let product = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)

        if vendor != 0 || product != 0 || serial != 0 {
            return "vendor:\(vendor):product:\(product):serial:\(serial)"
        }

        return "display:\(id)"
    }
}
