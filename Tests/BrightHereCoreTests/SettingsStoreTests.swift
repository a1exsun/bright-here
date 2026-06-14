import Foundation
import Testing
@testable import BrightHereCore

@Suite("Settings store")
struct SettingsStoreTests {
    @Test("uses expected defaults")
    func usesDefaults() {
        let defaults = UserDefaults(suiteName: "BrightHereTests.defaults")!
        defaults.removePersistentDomain(forName: "BrightHereTests.defaults")

        let settings = UserDefaultsSettingsStore(defaults: defaults).load()

        #expect(settings == AppSettings())
    }

    @Test("round trips settings")
    func roundTrips() {
        let defaults = UserDefaults(suiteName: "BrightHereTests.roundTrip")!
        defaults.removePersistentDomain(forName: "BrightHereTests.roundTrip")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let expected = AppSettings(isEnabled: false, launchAtLogin: true, showMenuBarIcon: true, brightnessStep: 0.1)

        store.save(expected)

        #expect(store.load() == expected)
    }
}
