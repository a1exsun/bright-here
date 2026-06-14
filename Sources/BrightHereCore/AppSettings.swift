import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var launchAtLogin: Bool
    public var showMenuBarIcon: Bool
    public var brightnessStep: Float

    public init(
        isEnabled: Bool = true,
        launchAtLogin: Bool = false,
        showMenuBarIcon: Bool = false,
        brightnessStep: Float = 0.0625
    ) {
        self.isEnabled = isEnabled
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.brightnessStep = brightnessStep
    }
}

public protocol SettingsStoring {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public final class UserDefaultsSettingsStore: SettingsStoring {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let brightnessStep = "brightnessStep"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        AppSettings(
            isEnabled: defaults.object(forKey: Key.isEnabled) as? Bool ?? true,
            launchAtLogin: defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false,
            showMenuBarIcon: defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? false,
            brightnessStep: defaults.object(forKey: Key.brightnessStep) as? Float ?? 0.0625
        )
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.isEnabled, forKey: Key.isEnabled)
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(settings.showMenuBarIcon, forKey: Key.showMenuBarIcon)
        defaults.set(settings.brightnessStep, forKey: Key.brightnessStep)
    }
}
