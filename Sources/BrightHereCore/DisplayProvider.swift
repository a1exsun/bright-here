import CoreGraphics

public protocol DisplayProviding {
    func allKnownDisplays() -> [ManagedDisplay]
}

public struct CoreGraphicsDisplayProvider: DisplayProviding {
    public init() {}

    public func allKnownDisplays() -> [ManagedDisplay] {
        var byID: [DisplayID: ManagedDisplay] = [:]
        for display in onlineDisplays() {
            byID[display.id] = display
        }
        for display in activeDisplays() where byID[display.id] == nil {
            byID[display.id] = display
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain {
                return lhs.isMain
            }
            return lhs.id < rhs.id
        }.enumerated().map { offset, display in
            makeDisplay(index: offset + 1, id: display.id, source: display.source)
        }
    }

    public func onlineDisplays() -> [ManagedDisplay] {
        displayList(source: "online", loader: CGGetOnlineDisplayList)
    }

    public func activeDisplays() -> [ManagedDisplay] {
        displayList(source: "active", loader: CGGetActiveDisplayList)
    }

    private func displayList(
        source: String,
        loader: (UInt32, UnsafeMutablePointer<DisplayID>?, UnsafeMutablePointer<UInt32>) -> CGError
    ) -> [ManagedDisplay] {
        var count: UInt32 = 0
        guard loader(0, nil, &count) == .success else {
            return []
        }

        var ids = Array(repeating: DisplayID(0), count: Int(count))
        guard loader(count, &ids, &count) == .success else {
            return []
        }

        return ids.prefix(Int(count)).enumerated().map { offset, id in
            makeDisplay(index: offset + 1, id: id, source: source)
        }
    }

    private func makeDisplay(index: Int, id: DisplayID, source: String) -> ManagedDisplay {
        ManagedDisplay(
            index: index,
            id: id,
            bounds: CGDisplayBounds(id),
            isMain: CGDisplayIsMain(id) != 0,
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            isActive: CGDisplayIsActive(id) != 0,
            isOnline: CGDisplayIsOnline(id) != 0,
            isAsleep: CGDisplayIsAsleep(id) != 0,
            source: source
        )
    }
}
