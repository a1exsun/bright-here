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
            brightnessStep: 0.1,
            brightnessControlMode: .gamma,
            displayBrightnessControlModes: [
                "vendor:1:product:2:serial:3": .ddcCI
            ]
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

    @Test("defaults brightness control mode to system")
    func defaultsBrightnessControlModeToSystem() {
        let defaults = UserDefaults(suiteName: "BrightHereTests.controlModeDefault")!
        defaults.removePersistentDomain(forName: "BrightHereTests.controlModeDefault")

        let settings = UserDefaultsSettingsStore(defaults: defaults).load()

        #expect(settings.brightnessControlMode == .system)
        #expect(settings.displayBrightnessControlModes.isEmpty)
    }

    @Test("uses display brightness control mode for external displays")
    func usesDisplayBrightnessControlModeForExternalDisplays() {
        var settings = AppSettings(brightnessControlMode: .gamma)
        let external = ManagedDisplay(
            index: 1,
            id: 123,
            bounds: .zero,
            isMain: true,
            isBuiltin: false,
            isActive: true,
            isOnline: true,
            isAsleep: false,
            source: "test"
        )
        let builtin = ManagedDisplay(
            index: 2,
            id: 456,
            bounds: .zero,
            isMain: false,
            isBuiltin: true,
            isActive: true,
            isOnline: true,
            isAsleep: false,
            source: "test"
        )

        #expect(settings.brightnessControlMode(for: external) == .gamma)
        settings.setBrightnessControlMode(.ddcCI, for: external)

        #expect(settings.brightnessControlMode(for: external) == .ddcCI)
        #expect(settings.brightnessControlMode(for: builtin) == .system)
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
