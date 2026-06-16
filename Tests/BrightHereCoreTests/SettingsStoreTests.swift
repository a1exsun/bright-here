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
        let expected = AppSettings(
            isEnabled: false,
            launchAtLogin: true,
            showMenuBarIcon: true,
            showBrightnessOverlay: false,
            autoUpdateEnabled: false,
            brightnessStep: 0.1
        )

        store.save(expected)

        #expect(store.load() == expected)
    }

    @Test("defaults brightness overlay to visible for existing users")
    func defaultsBrightnessOverlayToVisible() {
        let defaults = UserDefaults(suiteName: "BrightHereTests.overlayDefault")!
        defaults.removePersistentDomain(forName: "BrightHereTests.overlayDefault")

        let settings = UserDefaultsSettingsStore(defaults: defaults).load()

        #expect(settings.showBrightnessOverlay)
    }

    @Test("defaults automatic updates to enabled for existing users")
    func defaultsAutomaticUpdatesToEnabled() {
        let defaults = UserDefaults(suiteName: "BrightHereTests.autoUpdateDefault")!
        defaults.removePersistentDomain(forName: "BrightHereTests.autoUpdateDefault")

        let settings = UserDefaultsSettingsStore(defaults: defaults).load()

        #expect(settings.autoUpdateEnabled)
    }

    @Test("migrates legacy default brightness step")
    func migratesLegacyBrightnessStep() {
        let defaults = UserDefaults(suiteName: "BrightHereTests.legacyStep")!
        defaults.removePersistentDomain(forName: "BrightHereTests.legacyStep")
        defaults.set(Float(0.0625), forKey: "brightnessStep")

        let settings = UserDefaultsSettingsStore(defaults: defaults).load()

        #expect(settings.brightnessStep == AppSettings.defaultBrightnessStep)
    }
}
