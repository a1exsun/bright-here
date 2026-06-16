import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultBrightnessStep: Float = 0.03125

    public var isEnabled: Bool
    public var launchAtLogin: Bool
    public var showMenuBarIcon: Bool
    public var showBrightnessOverlay: Bool
    public var autoUpdateEnabled: Bool
    public var brightnessStep: Float
    public var brightnessControlMode: BrightnessControlMode

    public init(
        isEnabled: Bool = true,
        launchAtLogin: Bool = false,
        showMenuBarIcon: Bool = false,
        showBrightnessOverlay: Bool = true,
        autoUpdateEnabled: Bool = true,
        brightnessStep: Float = Self.defaultBrightnessStep,
        brightnessControlMode: BrightnessControlMode = .system
    ) {
        self.isEnabled = isEnabled
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.showBrightnessOverlay = showBrightnessOverlay
        self.autoUpdateEnabled = autoUpdateEnabled
        self.brightnessStep = brightnessStep
        self.brightnessControlMode = brightnessControlMode
    }
}

public protocol SettingsStoring {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public final class UserDefaultsSettingsStore: SettingsStoring {
    private static let legacyDefaultBrightnessStep: Float = 0.0625

    private enum Key {
        static let isEnabled = "isEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showBrightnessOverlay = "showBrightnessOverlay"
        static let autoUpdateEnabled = "autoUpdateEnabled"
        static let brightnessStep = "brightnessStep"
        static let brightnessControlMode = "brightnessControlMode"
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
            showBrightnessOverlay: defaults.object(forKey: Key.showBrightnessOverlay) as? Bool ?? true,
            autoUpdateEnabled: defaults.object(forKey: Key.autoUpdateEnabled) as? Bool ?? true,
            brightnessStep: loadedBrightnessStep(),
            brightnessControlMode: loadedBrightnessControlMode()
        )
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.isEnabled, forKey: Key.isEnabled)
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(settings.showMenuBarIcon, forKey: Key.showMenuBarIcon)
        defaults.set(settings.showBrightnessOverlay, forKey: Key.showBrightnessOverlay)
        defaults.set(settings.autoUpdateEnabled, forKey: Key.autoUpdateEnabled)
        defaults.set(settings.brightnessStep, forKey: Key.brightnessStep)
        defaults.set(settings.brightnessControlMode.rawValue, forKey: Key.brightnessControlMode)
    }

    private func loadedBrightnessStep() -> Float {
        guard let stored = defaults.object(forKey: Key.brightnessStep) as? Float else {
            return AppSettings.defaultBrightnessStep
        }

        if abs(stored - Self.legacyDefaultBrightnessStep) < 0.0001 {
            return AppSettings.defaultBrightnessStep
        }

        return stored
    }

    private func loadedBrightnessControlMode() -> BrightnessControlMode {
        guard let rawValue = defaults.object(forKey: Key.brightnessControlMode) as? String,
              let mode = BrightnessControlMode(rawValue: rawValue) else {
            return .system
        }
        return mode
    }
}
