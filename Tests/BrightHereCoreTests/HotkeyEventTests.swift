import Testing
@testable import BrightHereCore

@Suite("System-defined hotkey decoder")
struct HotkeyEventTests {
    @Test("decodes brightness down")
    func decodesBrightnessDown() {
        let decoder = SystemDefinedEventDecoder()
        let data1 = (SystemDefinedEventDecoder.brightnessDownKeyType << 16) | (SystemDefinedEventDecoder.keyDownState << 8)

        #expect(decoder.decode(subtype: SystemDefinedEventDecoder.auxControlButtonSubtype, data1: data1) == .brightnessDown)
    }

    @Test("decodes brightness up")
    func decodesBrightnessUp() {
        let decoder = SystemDefinedEventDecoder()
        let data1 = (SystemDefinedEventDecoder.brightnessUpKeyType << 16) | (SystemDefinedEventDecoder.keyDownState << 8)

        #expect(decoder.decode(subtype: SystemDefinedEventDecoder.auxControlButtonSubtype, data1: data1) == .brightnessUp)
    }

    @Test("ignores key up")
    func ignoresKeyUp() {
        let decoder = SystemDefinedEventDecoder()
        let data1 = (SystemDefinedEventDecoder.brightnessUpKeyType << 16) | (0x0B << 8)

        #expect(decoder.decode(subtype: SystemDefinedEventDecoder.auxControlButtonSubtype, data1: data1) == nil)
    }
}
