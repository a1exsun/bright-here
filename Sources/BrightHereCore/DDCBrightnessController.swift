import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.i2c
import IOKit.graphics

public enum DDCTransport: String, CaseIterable, Equatable, Sendable {
    case arm64AVService = "arm64-av-service"
    case i2cFramebuffer = "i2c-framebuffer"
}

public struct DDCBrightnessLastWrite: Equatable, Sendable {
    public let requestedBrightness: Float
    public let rawValue: UInt16
    public let rawMaximum: UInt16
    public let reportedMaximum: UInt16
    public let backend: DDCTransport?
    public let succeeded: Bool
    public let readbackBackend: DDCTransport?
    public let readbackRawCurrent: UInt16?
    public let readbackRawMaximum: UInt16?
}

public struct DDCTransportReadback: Equatable, Sendable {
    public let backend: DDCTransport
    public let rawCurrent: UInt16?
    public let rawMaximum: UInt16?
}

public struct DDCVCPFeatureReadback: Equatable, Sendable {
    public let code: UInt8
    public let backend: DDCTransport?
    public let rawCurrent: UInt16?
    public let rawMaximum: UInt16?
}

public struct DDCBrightnessDiagnostics: Equatable, Sendable {
    public let readBackend: DDCTransport?
    public let rawCurrent: UInt16?
    public let rawMaximum: UInt16?
    public let mappedRawMaximum: UInt16?
    public let mappedRawMaximumPercent: Float?
    public let mappedBrightness: Float?
    public let lastWrite: DDCBrightnessLastWrite?
    public let transportReadbacks: [DDCTransportReadback]
    public let vcpFeatureReadbacks: [DDCVCPFeatureReadback]
    public let lastError: String?
}

public final class DDCBrightnessController: BrightnessControlling, BrightnessControlResetting {
    private typealias IOAVService = CFTypeRef
    private typealias CGDisplayIOServicePortFn = @convention(c) (DisplayID) -> io_service_t
    private typealias IOAVServiceCreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<IOAVService>?
    private typealias IOAVServiceReadI2CFn = @convention(c) (IOAVService, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias IOAVServiceWriteI2CFn = @convention(c) (IOAVService, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private struct VCPValue {
        let current: UInt16
        let maximum: UInt16
    }

    struct LuminanceMapping {
        static let mappedMaximumRatio: Float = 0.40

        let reportedMaximum: UInt16

        var rawMaximum: UInt16 {
            let rawMaximum = floor(Float(max(1, reportedMaximum)) * Self.mappedMaximumRatio)
            return max(1, UInt16(rawMaximum))
        }

        var rawMaximumPercent: Float {
            Float(rawMaximum) / Float(max(1, reportedMaximum))
        }

        func normalized(current: UInt16) -> Float {
            Float(min(current, rawMaximum)) / Float(rawMaximum)
        }

        func rawValue(for normalized: Float) -> UInt16 {
            UInt16((Float(rawMaximum) * min(max(normalized, 0), 1)).rounded())
        }
    }

    private struct Arm64ServiceCandidate {
        let productName: String
        let productID: Int
        let serialNumber: Int
        let service: IOAVService
    }

    private static let luminanceCode: UInt8 = 0x10
    private static let debugVCPFeatureCodes: [UInt8] = [0x10, 0x12, 0x13, 0xD6]
    private static let arm64DDCAddress: UInt8 = 0x37
    private static let arm64DDCDataAddress: UInt8 = 0x51
    private let coreGraphics: UnsafeMutableRawPointer?
    private let ioKit: UnsafeMutableRawPointer?
    private let displayIOServicePort: CGDisplayIOServicePortFn?
    private let ioAVServiceCreateWithService: IOAVServiceCreateWithServiceFn?
    private let ioAVServiceReadI2C: IOAVServiceReadI2CFn?
    private let ioAVServiceWriteI2C: IOAVServiceWriteI2CFn?
    private var maximumValues: [DisplayID: UInt16] = [:]
    private var values: [DisplayID: Float] = [:]
    private var originalValues: [DisplayID: Float] = [:]
    private var arm64Services: [DisplayID: IOAVService] = [:]
    private var lastWrites: [DisplayID: DDCBrightnessLastWrite] = [:]
    private var lastErrors: [DisplayID: String] = [:]

    public private(set) var lastError: String?

    public init() {
        coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        if let coreGraphics, let symbol = dlsym(coreGraphics, "CGDisplayIOServicePort") {
            displayIOServicePort = unsafeBitCast(symbol, to: CGDisplayIOServicePortFn.self)
        } else {
            displayIOServicePort = nil
        }
        ioAVServiceCreateWithService = Self.load(ioKit, "IOAVServiceCreateWithService", as: IOAVServiceCreateWithServiceFn.self)
        ioAVServiceReadI2C = Self.load(ioKit, "IOAVServiceReadI2C", as: IOAVServiceReadI2CFn.self)
        ioAVServiceWriteI2C = Self.load(ioKit, "IOAVServiceWriteI2C", as: IOAVServiceWriteI2CFn.self)
    }

    deinit {
        if let coreGraphics {
            dlclose(coreGraphics)
        }
        if let ioKit {
            dlclose(ioKit)
        }
    }

    public func brightness(for displayID: DisplayID) -> Float? {
        if let read = readVCPWithBackend(Self.luminanceCode, displayID: displayID), read.value.maximum > 0 {
            let value = read.value
            maximumValues[displayID] = value.maximum
            let normalized = luminanceMapping(reportedMaximum: value.maximum).normalized(current: value.current)
            values[displayID] = normalized
            clearError(for: displayID)
            return normalized
        }

        recordError("DDC/CI read failed for displayID=\(displayID)", for: displayID)
        return nil
    }

    public func diagnostics(for displayID: DisplayID) -> DDCBrightnessDiagnostics {
        let transportReadbacks = ddcTransportReadbacks(for: displayID)
        let read = readVCPWithBackend(Self.luminanceCode, displayID: displayID)
        let mapping = read.map { LuminanceMapping(reportedMaximum: $0.value.maximum) }
        if let read {
            maximumValues[displayID] = read.value.maximum
        }

        return DDCBrightnessDiagnostics(
            readBackend: read?.backend,
            rawCurrent: read?.value.current,
            rawMaximum: read?.value.maximum,
            mappedRawMaximum: mapping?.rawMaximum,
            mappedRawMaximumPercent: mapping?.rawMaximumPercent,
            mappedBrightness: read.map { LuminanceMapping(reportedMaximum: $0.value.maximum).normalized(current: $0.value.current) },
            lastWrite: lastWrites[displayID],
            transportReadbacks: transportReadbacks,
            vcpFeatureReadbacks: ddcVCPFeatureReadbacks(for: displayID),
            lastError: lastErrors[displayID]
        )
    }

    @discardableResult
    public func setBrightness(_ brightness: Float, for displayID: DisplayID) -> Bool {
        let value = min(max(brightness, 0), 1)
        rememberOriginalBrightnessIfNeeded(for: displayID)
        return setHardwareBrightness(value, for: displayID)
    }

    public func reset() {
        for (displayID, value) in Array(originalValues) {
            if setHardwareBrightness(value, for: displayID) {
                originalValues.removeValue(forKey: displayID)
            }
        }
    }

    public func reset(displayID: DisplayID) {
        guard let originalValue = originalValues[displayID] else {
            return
        }

        if setHardwareBrightness(originalValue, for: displayID) {
            originalValues.removeValue(forKey: displayID)
        }
    }

    private func rememberOriginalBrightnessIfNeeded(for displayID: DisplayID) {
        guard originalValues[displayID] == nil else {
            return
        }

        if let value = values[displayID] ?? currentHardwareBrightness(for: displayID) {
            originalValues[displayID] = value
        }
    }

    private func currentHardwareBrightness(for displayID: DisplayID) -> Float? {
        if let read = readVCPWithBackend(Self.luminanceCode, displayID: displayID), read.value.maximum > 0 {
            let value = read.value
            maximumValues[displayID] = value.maximum
            let normalized = luminanceMapping(reportedMaximum: value.maximum).normalized(current: value.current)
            values[displayID] = normalized
            return normalized
        }

        return nil
    }

    @discardableResult
    private func setHardwareBrightness(_ brightness: Float, for displayID: DisplayID) -> Bool {
        let value = min(max(brightness, 0), 1)
        let maximum = maximumValues[displayID]
            ?? readVCPWithBackend(Self.luminanceCode, displayID: displayID)?.value.maximum
            ?? 100
        if maximum > 0 {
            maximumValues[displayID] = maximum
            let mapping = luminanceMapping(reportedMaximum: maximum)
            let rawValue = mapping.rawValue(for: value)
            let backend = writeVCPWithBackend(Self.luminanceCode, value: rawValue, displayID: displayID)
            let readback = readVCPWithBackend(Self.luminanceCode, displayID: displayID)
            lastWrites[displayID] = DDCBrightnessLastWrite(
                requestedBrightness: value,
                rawValue: rawValue,
                rawMaximum: mapping.rawMaximum,
                reportedMaximum: maximum,
                backend: backend,
                succeeded: backend != nil,
                readbackBackend: readback?.backend,
                readbackRawCurrent: readback?.value.current,
                readbackRawMaximum: readback?.value.maximum
            )
            if backend != nil {
                values[displayID] = value
                clearError(for: displayID)
                return true
            }
        }

        recordError("DDC/CI hardware write failed for displayID=\(displayID)", for: displayID)
        return false
    }

    private func recordError(_ message: String, for displayID: DisplayID) {
        lastErrors[displayID] = message
        lastError = message
    }

    private func clearError(for displayID: DisplayID) {
        lastErrors.removeValue(forKey: displayID)
        lastError = lastErrors.values.first
    }

    private func luminanceMapping(reportedMaximum: UInt16) -> LuminanceMapping {
        LuminanceMapping(reportedMaximum: reportedMaximum)
    }

    private func readVCPWithBackend(_ code: UInt8, displayID: DisplayID) -> (value: VCPValue, backend: DDCTransport)? {
        if let value = readArm64VCP(code, displayID: displayID) {
            return (value, .arm64AVService)
        }
        if let value = readVCP(code, displayID: displayID) {
            return (value, .i2cFramebuffer)
        }
        return nil
    }

    private func ddcTransportReadbacks(for displayID: DisplayID) -> [DDCTransportReadback] {
        DDCTransport.allCases.map { backend in
            let value = readVCP(Self.luminanceCode, displayID: displayID, backend: backend)
            return DDCTransportReadback(
                backend: backend,
                rawCurrent: value?.current,
                rawMaximum: value?.maximum
            )
        }
    }

    private func ddcVCPFeatureReadbacks(for displayID: DisplayID) -> [DDCVCPFeatureReadback] {
        Self.debugVCPFeatureCodes.map { code in
            let read = readVCPWithBackend(code, displayID: displayID)
            return DDCVCPFeatureReadback(
                code: code,
                backend: read?.backend,
                rawCurrent: read?.value.current,
                rawMaximum: read?.value.maximum
            )
        }
    }

    private func readVCP(_ code: UInt8, displayID: DisplayID, backend: DDCTransport) -> VCPValue? {
        switch backend {
        case .arm64AVService:
            readArm64VCP(code, displayID: displayID)
        case .i2cFramebuffer:
            readVCP(code, displayID: displayID)
        }
    }

    private func writeVCPWithBackend(_ code: UInt8, value: UInt16, displayID: DisplayID) -> DDCTransport? {
        if writeArm64VCP(code, value: value, displayID: displayID) {
            return .arm64AVService
        }
        if writeVCP(code, value: value, displayID: displayID) {
            return .i2cFramebuffer
        }
        return nil
    }

    private func readArm64VCP(_ code: UInt8, displayID: DisplayID) -> VCPValue? {
        guard let service = arm64Service(for: displayID) else {
            return nil
        }

        var send = [code]
        var reply = [UInt8](repeating: 0, count: 11)
        guard performArm64DDC(service: service, send: &send, reply: &reply) else {
            return nil
        }

        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0 else {
            return nil
        }

        return VCPValue(current: min(current, maximum), maximum: maximum)
    }

    private func writeArm64VCP(_ code: UInt8, value: UInt16, displayID: DisplayID) -> Bool {
        guard let service = arm64Service(for: displayID) else {
            return false
        }

        var send = [code, UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        var reply: [UInt8] = []
        return performArm64DDC(service: service, send: &send, reply: &reply)
    }

    private func performArm64DDC(service: IOAVService, send: inout [UInt8], reply: inout [UInt8]) -> Bool {
        guard let ioAVServiceWriteI2C else {
            return false
        }

        let dataAddress = Self.arm64DDCDataAddress
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let checksumSeed = send.count == 1
            ? Self.arm64DDCAddress << 1
            : Self.arm64DDCAddress << 1 ^ dataAddress
        packet[packet.count - 1] = arm64Checksum(seed: checksumSeed, data: packet, end: packet.count - 2)

        let writeCycleCount = 2
        var success = false
        for _ in 0..<5 {
            let packetCount = packet.count
            for _ in 0..<writeCycleCount {
                usleep(10_000)
                success = packet.withUnsafeMutableBufferPointer { buffer in
                    guard let base = buffer.baseAddress else {
                        return false
                    }
                    return ioAVServiceWriteI2C(service, UInt32(Self.arm64DDCAddress), UInt32(dataAddress), base, UInt32(packetCount)) == kIOReturnSuccess
                }

            }

            if !reply.isEmpty, let ioAVServiceReadI2C {
                usleep(50_000)
                let replyCount = reply.count
                success = reply.withUnsafeMutableBufferPointer { buffer in
                    guard let base = buffer.baseAddress else {
                        return false
                    }
                    return ioAVServiceReadI2C(service, UInt32(Self.arm64DDCAddress), 0, base, UInt32(replyCount)) == kIOReturnSuccess
                }

                if success {
                    success = arm64Checksum(seed: 0x50, data: reply, end: reply.count - 2) == reply[reply.count - 1]
                }
            }

            if success {
                return true
            }
            usleep(20_000)
        }

        return false
    }

    private func arm64Checksum(seed: UInt8, data: [UInt8], end: Int) -> UInt8 {
        guard end >= 0 else {
            return seed
        }

        var checksum = seed
        for index in 0...end {
            checksum ^= data[index]
        }
        return checksum
    }

    private func arm64Service(for displayID: DisplayID) -> IOAVService? {
        if let service = arm64Services[displayID] {
            return service
        }

        let bestMatch = arm64ServiceCandidates()
            .map { candidate in
                (candidate: candidate, score: arm64MatchScore(candidate, displayID: displayID))
            }
            .filter { $0.score > 0 }
            .max { first, second in
                first.score < second.score
            }?.candidate

        guard let service = bestMatch?.service else {
            return nil
        }

        arm64Services[displayID] = service
        return service
    }

    private func arm64MatchScore(_ candidate: Arm64ServiceCandidate, displayID: DisplayID) -> Int {
        var score = 0
        if candidate.productID != 0, candidate.productID == Int(CGDisplayModelNumber(displayID)) {
            score += 10
        }
        if candidate.serialNumber != 0, candidate.serialNumber == Int(CGDisplaySerialNumber(displayID)) {
            score += 10
        }
        return score
    }

    private func arm64ServiceCandidates() -> [Arm64ServiceCandidate] {
        guard let ioAVServiceCreateWithService else {
            return []
        }

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else {
            return []
        }
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [Arm64ServiceCandidate] = []
        var currentProductName = ""
        var currentProductID = 0
        var currentSerialNumber = 0

        while true {
            let entry = IOIteratorNext(iterator)
            if entry == IO_OBJECT_NULL {
                break
            }
            defer { IOObjectRelease(entry) }

            let name = registryEntryName(entry)
            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                let attributes = displayAttributes(from: entry)
                currentProductName = attributes.productName
                currentProductID = attributes.productID
                currentSerialNumber = attributes.serialNumber
                continue
            }

            guard name == "DCPAVServiceProxy",
                  registryStringProperty(entry, key: "Location") == "External",
                  let service = ioAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
                continue
            }

            candidates.append(
                Arm64ServiceCandidate(
                    productName: currentProductName,
                    productID: currentProductID,
                    serialNumber: currentSerialNumber,
                    service: service
                )
            )
        }

        return candidates
    }

    private func registryEntryName(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else {
            return ""
        }
        let endIndex = name.firstIndex(of: 0) ?? name.endIndex
        return String(decoding: name[..<endIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func displayAttributes(from entry: io_registry_entry_t) -> (productName: String, productID: Int, serialNumber: Int) {
        guard let attributes = registryProperty(entry, key: "DisplayAttributes") as? NSDictionary,
              let productAttributes = attributes["ProductAttributes"] as? NSDictionary else {
            return ("", 0, 0)
        }

        let productName = productAttributes["ProductName"] as? String ?? ""
        let productID = intValue(productAttributes["ProductID"])
        let serialNumber = intValue(productAttributes["SerialNumber"])
        return (productName, productID, serialNumber)
    }

    private func registryStringProperty(_ entry: io_registry_entry_t, key: String) -> String? {
        registryProperty(entry, key: key) as? String
    }

    private func registryProperty(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue()
    }

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as UInt32:
            return Int(value)
        default:
            return 0
        }
    }

    private func readVCP(_ code: UInt8, displayID: DisplayID) -> VCPValue? {
        let packet = ddcPacket(payload: [0x01, code])
        guard let reply = transact(displayID: displayID, send: packet, replySize: 16) else {
            return nil
        }

        for index in reply.indices where reply[index] == code {
            let maxHigh = index + 2
            let currentHigh = index + 4
            guard currentHigh + 1 < reply.count else {
                continue
            }

            let maximum = UInt16(reply[maxHigh]) << 8 | UInt16(reply[maxHigh + 1])
            let current = UInt16(reply[currentHigh]) << 8 | UInt16(reply[currentHigh + 1])
            if maximum > 0 {
                return VCPValue(current: min(current, maximum), maximum: maximum)
            }
        }

        return nil
    }

    private func writeVCP(_ code: UInt8, value: UInt16, displayID: DisplayID) -> Bool {
        let packet = ddcPacket(payload: [
            0x03,
            code,
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
        return transact(displayID: displayID, send: packet, replySize: 0) != nil
    }

    private func ddcPacket(payload: [UInt8]) -> [UInt8] {
        let length = UInt8(0x80 | payload.count)
        var packet: [UInt8] = [0x51, length]
        packet.append(contentsOf: payload)
        packet.append(ddcChecksum(packet))
        return packet
    }

    private func ddcChecksum(_ packet: [UInt8]) -> UInt8 {
        packet.reduce(UInt8(0x6e)) { partial, byte in
            partial ^ byte
        }
    }

    private func transact(displayID: DisplayID, send: [UInt8], replySize: Int) -> [UInt8]? {
        guard let framebuffer = framebufferService(for: displayID) else {
            return nil
        }

        var count: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &count) == kIOReturnSuccess, count > 0 else {
            return nil
        }

        for bus in 0..<count {
            var interface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(framebuffer, IOOptionBits(bus), &interface) == kIOReturnSuccess else {
                continue
            }
            defer { IOObjectRelease(interface) }

            guard let reply = transact(interface: interface, send: send, replySize: replySize) else {
                continue
            }
            return reply
        }

        return nil
    }

    private func transact(interface: io_service_t, send: [UInt8], replySize: Int) -> [UInt8]? {
        var connect: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(interface, 0, &connect) == kIOReturnSuccess, let connect else {
            return nil
        }
        defer { IOI2CInterfaceClose(connect, 0) }

        var request = IOI2CRequest()
        var sendBytes = send
        var reply = [UInt8](repeating: 0, count: max(replySize, 1))

        let requestStarted = sendBytes.withUnsafeMutableBufferPointer { sendBuffer in
            reply.withUnsafeMutableBufferPointer { replyBuffer in
                guard let sendBase = sendBuffer.baseAddress,
                      let replyBase = replyBuffer.baseAddress else {
                    return false
                }

                request.sendAddress = 0x6e
                request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                request.sendBuffer = vm_address_t(UInt(bitPattern: sendBase))
                request.sendBytes = UInt32(send.count)
                request.replyAddress = replySize > 0 ? 0x6f : 0
                request.replyTransactionType = replySize > 0 ? IOOptionBits(kIOI2CDDCciReplyTransactionType) : IOOptionBits(kIOI2CNoTransactionType)
                request.replyBuffer = vm_address_t(UInt(bitPattern: replyBase))
                request.replyBytes = UInt32(replySize)
                request.minReplyDelay = 50_000_000

                return IOI2CSendRequest(connect, 0, &request) == kIOReturnSuccess
            }
        }

        guard requestStarted, request.result == kIOReturnSuccess else {
            return nil
        }

        if replySize == 0 {
            return []
        }

        return Array(reply.prefix(Int(request.replyBytes)))
    }

    private func framebufferService(for displayID: DisplayID) -> io_service_t? {
        guard let displayIOServicePort else {
            return nil
        }

        let service = displayIOServicePort(displayID)
        return service == 0 ? nil : service
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer?, _ symbol: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }
}
