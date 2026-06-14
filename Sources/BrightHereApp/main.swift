import AppKit
import ApplicationServices
import BrightHereCore
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var permissionStatus: String = ""
    @Published var runtimeStatus: String = "Ready"

    private let store: SettingsStoring
    private weak var coordinator: AppCoordinator?

    init(store: SettingsStoring, coordinator: AppCoordinator) {
        self.store = store
        self.coordinator = coordinator
        settings = store.load()
        refreshPermissionStatus()
    }

    func save() {
        store.save(settings)
        coordinator?.settingsDidChange(settings)
    }

    func refreshPermissionStatus() {
        permissionStatus = PermissionController.isAccessibilityTrusted ? "Ready" : "Accessibility permission required"
    }

    func openAccessibilitySettings() {
        PermissionController.openAccessibilitySettings()
        refreshPermissionStatus()
    }

    func checkForUpdates() {
        coordinator?.checkForUpdates()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemController.setEnabled(enabled)
            settings.launchAtLogin = enabled
            save()
        } catch {
            runtimeStatus = "Could not update login item: \(error.localizedDescription)"
            settings.launchAtLogin = LoginItemController.isEnabled
        }
    }
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let store = UserDefaultsSettingsStore()
    private let displayProvider = CoreGraphicsDisplayProvider()
    private let brightness = NativeBrightnessController()
    private let locator = DisplayLocator()
    private let decoder = SystemDefinedEventDecoder()
    private let updater = SparkleUpdateController()

    private var model: AppModel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var eventTap: EventTapController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel(store: store, coordinator: self)
        settingsDidChange(model.settings)
        startEventTap()

        if !PermissionController.isAccessibilityTrusted || CommandLine.arguments.contains("--show-settings") {
            showSettingsWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func settingsDidChange(_ settings: AppSettings) {
        configureStatusItem(show: settings.showMenuBarIcon)
        model?.refreshPermissionStatus()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    private func startEventTap() {
        eventTap = EventTapController { [weak self] event in
            self?.handleSystemDefinedEvent(event) ?? false
        }
        if eventTap?.start() == true {
            model?.runtimeStatus = "Brightness keys active"
        } else {
            model?.runtimeStatus = "Could not start brightness key listener"
        }
    }

    private func handleSystemDefinedEvent(_ event: CGEvent) -> Bool {
        guard model.settings.isEnabled else {
            return false
        }
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return false
        }
        guard let keyEvent = decoder.decode(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1) else {
            return false
        }

        let direction: BrightnessDirection = keyEvent == .brightnessUp ? .up : .down
        let point = event.location
        let displays = displayProvider.allKnownDisplays()
        guard let display = locator.display(containing: point, displays: displays) else {
            model.runtimeStatus = "No display at pointer"
            return true
        }

        let adjuster = BrightnessAdjuster(step: model.settings.brightnessStep)
        if let result = adjuster.adjust(displayID: display.id, direction: direction, brightness: brightness) {
            model.runtimeStatus = "\(display.friendlyName): \(Int((result.newValue * 100).rounded()))%"
        } else {
            model.runtimeStatus = "Could not adjust \(display.friendlyName)"
        }

        return true
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let view = SettingsView(model: model)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Bright Here"
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStatusItem(show: Bool) {
        if show {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Bright Here")

                let menu = NSMenu()
                menu.addItem(NSMenuItem(title: "Open Bright Here", action: #selector(openSettingsFromMenu), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q"))
                item.menu = menu
                statusItem = item
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func openSettingsFromMenu() {
        showSettingsWindow()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}

final class EventTapController {
    private let handler: (CGEvent) -> Bool
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping (CGEvent) -> Bool) {
        self.handler = handler
    }

    func start() -> Bool {
        let systemDefinedEventType = UInt32(NSEvent.EventType.systemDefined.rawValue)
        let mask = CGEventMask(1 << systemDefinedEventType)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
                    if let refcon {
                        let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
                        controller.enable()
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handler(event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        enable()
        return true
    }

    func enable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

enum PermissionController {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LoginItemController {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class SparkleUpdateController {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 18) {
                controls
                githubModule
            }
            .padding(20)

            Divider()
            HStack {
                Text(model.runtimeStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max")
                .font(.title2)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Bright Here")
                    .font(.title3.weight(.semibold))
                Text("Brightness follows your pointer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Enable F1/F2 brightness routing", isOn: binding(\.isEnabled))
            Toggle("Launch at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Toggle("Show menu bar icon", isOn: binding(\.showMenuBarIcon))

            HStack {
                Text("Step")
                Slider(value: Binding(
                    get: { Double(model.settings.brightnessStep) },
                    set: {
                        model.settings.brightnessStep = Float($0)
                        model.save()
                    }
                ), in: 0.01...0.15)
                Text("\(Int((model.settings.brightnessStep * 100).rounded()))%")
                    .frame(width: 42, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack {
                Text(model.permissionStatus)
                    .font(.footnote)
                    .foregroundColor(PermissionController.isAccessibilityTrusted ? .secondary : .orange)
                Spacer()
                Button("Open Permissions") {
                    model.openAccessibilitySettings()
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var githubModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                Spacer()
                Button("Check for Updates") {
                    model.checkForUpdates()
                }
            }

            Text("Release notes, issues, and update metadata will be filled in here.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Link("a1exsun/bright-here", destination: URL(string: "https://github.com/a1exsun/bright-here")!)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                model.settings[keyPath: keyPath] = $0
                model.save()
            }
        )
    }
}

let app = NSApplication.shared
let delegate = AppCoordinator()
app.delegate = delegate
app.run()
