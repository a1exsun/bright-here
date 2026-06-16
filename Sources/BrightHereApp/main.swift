import AppKit
import ApplicationServices
import BrightHereCore
import OSLog
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var permissionStatus: String = ""
    @Published var runtimeStatus: String = "Ready"
    @Published var isAccessibilityTrusted = false
    @Published var isHotkeyListenerActive = false

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
        isAccessibilityTrusted = PermissionController.isAccessibilityTrusted
        permissionStatus = isAccessibilityTrusted ? "Accessibility permission granted" : "Accessibility permission required"
    }

    func setHotkeyListenerActive(_ active: Bool) {
        isHotkeyListenerActive = active
    }

    func openAccessibilitySettings() {
        PermissionController.openAccessibilitySettings()
        refreshPermissionStatus()
    }

    func checkForUpdates() {
        coordinator?.checkForUpdates()
    }

    func openDebugWindow() {
        coordinator?.showDebugWindow()
    }

    func reportIssue() {
        coordinator?.reportIssue()
    }

    func testBrightness(_ direction: BrightnessDirection) {
        coordinator?.testBrightness(direction)
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

    func setShowMenuBarIcon(_ enabled: Bool) {
        if !enabled, coordinator?.confirmHidingMenuBarIcon() == false {
            settings.showMenuBarIcon = true
            return
        }

        settings.showMenuBarIcon = enabled
        save()
    }

    func quit() {
        coordinator?.quit()
    }
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private static let showSettingsNotification = Notification.Name("dev.xsun.brighthere.showSettings")
    private let store = UserDefaultsSettingsStore()
    private let displayProvider = CoreGraphicsDisplayProvider()
    private let pointerLocator = CoreGraphicsPointerLocator()
    private let brightness = NativeBrightnessController()
    private let locator = DisplayLocator()
    private let decoder = SystemDefinedEventDecoder()
    private let log = AppLog()
    private let brightnessOverlay = BrightnessOverlayPresenter()
    private lazy var updater = SparkleUpdateController(log: log) { [weak self] status in
        self?.model?.runtimeStatus = status
    }

    private var model: AppModel!
    private var settingsWindow: NSWindow?
    private var debugWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var eventTap: EventTapController?
    private var eventTapStarted = false
    private var didLogMissingAccessibilityPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Self.requestExistingInstanceToShowSettingsIfNeeded() {
            NSApp.terminate(nil)
            return
        }

        model = AppModel(store: store, coordinator: self)
        observeShowSettingsRequests()
        log.info("App launched version=\(Self.appVersion) macOS=\(Self.macOSVersion)")
        log.info("Accessibility trusted=\(PermissionController.isAccessibilityTrusted)")
        updater.start()
        settingsDidChange(model.settings)
        startEventTap()

        if !PermissionController.isAccessibilityTrusted || CommandLine.arguments.contains("--show-settings") {
            showSettingsWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshPermissionStatus()
        startEventTap()
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

    func confirmHidingMenuBarIcon() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon?"
        alert.informativeText = "Bright Here will keep running in the background. To reopen settings or quit later, launch Bright Here again from Applications, Launchpad, or Spotlight."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Keep Icon")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func showDebugWindow() {
        if debugWindow == nil {
            let view = DebugView(model: model, viewModel: DebugViewModel(
                displayProvider: self.displayProvider,
                pointerLocator: self.pointerLocator,
                brightness: self.brightness
            ))
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Bright Here Debug"
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            debugWindow = window
        }

        debugWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func testBrightness(_ direction: BrightnessDirection) {
        let result = routeBrightness(direction: direction, source: "debug-test")
        if result == nil {
            model.runtimeStatus = "Debug test could not route brightness"
        }
    }

    func reportIssue() {
        let diagnostics = DiagnosticsCollector(
            displayProvider: displayProvider,
            pointerLocator: pointerLocator,
            brightness: brightness
        ).snapshot()
        let context = IssueReportContext(
            version: Self.appVersion,
            macOSVersion: Self.macOSVersion,
            permissionStatus: model.permissionStatus,
            runtimeStatus: model.runtimeStatus,
            pointerDiagnostics: diagnostics,
            recentErrorLog: log.recentErrorLogText()
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(IssueReporter.clipboardText(context: context), forType: .string)
        NSWorkspace.shared.open(IssueReporter.issueURL(context: context))
        model.runtimeStatus = "Recent error logs copied. Paste them into the GitHub issue if needed."
        log.info("Opened GitHub issue URL and copied recent error logs")
    }

    private func startEventTap() {
        guard !eventTapStarted else {
            model?.setHotkeyListenerActive(true)
            return
        }

        guard PermissionController.isAccessibilityTrusted else {
            model?.refreshPermissionStatus()
            model?.setHotkeyListenerActive(false)
            model?.runtimeStatus = "Accessibility permission required"
            if !didLogMissingAccessibilityPermission {
                didLogMissingAccessibilityPermission = true
                log.error("Event tap not started: accessibility permission missing")
            }
            return
        }
        didLogMissingAccessibilityPermission = false

        eventTap = EventTapController { [weak self] event in
            self?.handleSystemDefinedEvent(event) ?? false
        }
        if eventTap?.start() == true {
            eventTapStarted = true
            model?.setHotkeyListenerActive(true)
            model?.runtimeStatus = "Brightness keys active"
            log.info("Event tap started")
        } else {
            eventTapStarted = false
            model?.setHotkeyListenerActive(false)
            model?.runtimeStatus = "Could not start brightness key listener"
            log.error("Event tap failed to start")
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
        _ = routeBrightness(direction: direction, source: "hotkey")

        return true
    }

    @discardableResult
    private func routeBrightness(direction: BrightnessDirection, source: String) -> BrightnessRoutingResult? {
        let router = BrightnessRouter(
            displayProvider: displayProvider,
            pointerLocator: pointerLocator,
            displayLocator: locator,
            brightness: brightness
        )

        guard let result = router.route(direction: direction, step: model.settings.brightnessStep) else {
            let point = pointerLocator.currentPointerLocation()
            let displays = displayProvider.allKnownDisplays()
            model.runtimeStatus = "Could not route brightness"
            log.error("\(source) route failed direction=\(direction) pointer=\(DiagnosticsFormatter.point(point)) displays=\(displays.count)")
            return nil
        }

        log.info(
            "\(source) routed direction=\(direction) pointer=\(DiagnosticsFormatter.point(result.pointerLocation)) displayID=\(result.display.id) bounds=\(DiagnosticsFormatter.rect(result.display.bounds)) old=\(result.adjustment.oldValue) new=\(result.adjustment.newValue)"
        )

        if model.settings.showBrightnessOverlay {
            let display = result.display
            brightnessOverlay.show(
                level: BrightnessIndicatorState(value: result.adjustment.newValue),
                on: display,
                onValueChange: { [weak self] value in
                    guard let self else {
                        return
                    }

                    guard self.brightness.setBrightness(value, for: display.id) else {
                        self.model.runtimeStatus = "Could not set brightness from slider"
                        self.log.error("overlay slider failed displayID=\(display.id) value=\(value)")
                        return
                    }
                }
            )
        }
        return result
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let view = SettingsView(model: model)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 540),
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

    @objc private func showSettingsFromDistributedNotification(_ notification: Notification) {
        showSettingsWindow()
    }

    private func observeShowSettingsRequests() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showSettingsFromDistributedNotification),
            name: Self.showSettingsNotification,
            object: nil
        )
    }

    private static func requestExistingInstanceToShowSettingsIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let hasExistingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != currentPID }

        if hasExistingInstance {
            DistributedNotificationCenter.default().postNotificationName(
                showSettingsNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }

        return hasExistingInstance
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static var macOSVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
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

final class AppLog {
    private let logger = Logger(subsystem: "dev.xsun.brighthere", category: "runtime")
    private let writer: LogWriting

    init(writer: LogWriting = LogFileWriter()) {
        self.writer = writer
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        writer.append("INFO \(message)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writer.append("ERROR \(message)")
    }

    func recentLogText() -> String {
        writer.recentLogText(maxBytes: 64 * 1024)
    }

    func recentErrorLogText() -> String {
        writer.recentErrorLogText(maxBytes: 64 * 1024)
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
final class BrightnessOverlayPresenter {
    private var panel: BrightnessOverlayPanel?
    private var hostingView: NSHostingView<BrightnessOverlayView>?
    private var hideTimer: Timer?
    private let overlayModel = BrightnessOverlayModel()

    func show(
        level: BrightnessIndicatorState,
        on display: ManagedDisplay,
        onValueChange: @escaping (Float) -> Void
    ) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        overlayModel.configure(
            level: level,
            onValueChange: onValueChange,
            onEditingChanged: { [weak self] isEditing in
                if isEditing {
                    self?.hideTimer?.invalidate()
                } else {
                    self?.scheduleHide()
                }
            }
        )

        let hostingView = self.hostingView ?? NSHostingView(rootView: BrightnessOverlayView(model: overlayModel))
        hostingView.rootView = BrightnessOverlayView(model: overlayModel)
        panel.contentView = hostingView
        self.hostingView = hostingView

        position(panel, on: Self.screen(for: display) ?? NSScreen.main)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        scheduleHideIfNeeded()
    }

    private func makePanel() -> BrightnessOverlayPanel {
        BrightnessOverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 58))
    }

    private func scheduleHideIfNeeded() {
        guard !overlayModel.isEditing else {
            return
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.35, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        let frame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        ))
    }

    private static func screen(for display: ManagedDisplay) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == display.id
        }
    }
}

final class BrightnessOverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class BrightnessOverlayModel: ObservableObject {
    @Published var value: Double = 0
    @Published private(set) var isEditing = false

    private var onValueChange: ((Float) -> Void)?
    private var onEditingChanged: ((Bool) -> Void)?

    var percent: Int {
        BrightnessIndicatorState(value: Float(value)).percent
    }

    var symbolName: String {
        value <= 0.08 ? "sun.min.fill" : "sun.max.fill"
    }

    func configure(
        level: BrightnessIndicatorState,
        onValueChange: @escaping (Float) -> Void,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        value = Double(level.normalizedValue)
        self.onValueChange = onValueChange
        self.onEditingChanged = onEditingChanged
    }

    func setValueFromSlider(_ newValue: Double) {
        value = min(max(newValue, 0), 1)
        onValueChange?(Float(value))
    }

    func setEditing(_ editing: Bool) {
        isEditing = editing
        onEditingChanged?(editing)
    }
}

struct BrightnessOverlayView: View {
    @ObservedObject var model: BrightnessOverlayModel

    var body: some View {
        ZStack {
            NativeVisualEffectBackground(material: .hudWindow)

            HStack(spacing: 12) {
                Image(systemName: model.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)

                Slider(
                    value: Binding(
                        get: { model.value },
                        set: { model.setValueFromSlider($0) }
                    ),
                    in: 0...1,
                    onEditingChanged: { model.setEditing($0) }
                )

                Text("\(model.percent)%")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 340, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(model.percent)%")
    }
}

struct NativeVisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = .active
    }
}

@MainActor
final class SparkleUpdateController: NSObject, SPUUpdaterDelegate {
    private let log: AppLog
    private let statusHandler: (String) -> Void
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(log: AppLog, statusHandler: @escaping (String) -> Void) {
        self.log = log
        self.statusHandler = statusHandler
        super.init()
    }

    func start() {
        updaterController.startUpdater()
        log.info("Sparkle updater started")
    }

    func checkForUpdates() {
        guard updaterController.updater.canCheckForUpdates else {
            statusHandler("Update check unavailable")
            log.error("Manual update check unavailable")
            let alert = NSAlert()
            alert.messageText = "Update Check Unavailable"
            alert.informativeText = "Bright Here is already checking for updates, or the updater is not ready yet. Try again in a moment."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        statusHandler("Checking for updates...")
        log.info("Manual update check requested")
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        statusHandler("Update found: \(item.displayVersionString)")
        log.info("Sparkle found update version=\(item.versionString) displayVersion=\(item.displayVersionString)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        statusHandler("Bright Here is up to date")
        log.info("Sparkle did not find update: \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        statusHandler("Update download failed")
        log.error("Sparkle failed to download update version=\(item.versionString): \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        statusHandler("Update check failed")
        log.error("Sparkle update check failed: \(error.localizedDescription)")
    }
}

@MainActor
final class DebugViewModel: ObservableObject {
    @Published var diagnostics: PointerDiagnostics
    @Published var nsEventMouseLocation: CGPoint = .zero

    private let collector: DiagnosticsCollector

    init(
        displayProvider: DisplayProviding,
        pointerLocator: PointerLocating,
        brightness: BrightnessControlling
    ) {
        collector = DiagnosticsCollector(
            displayProvider: displayProvider,
            pointerLocator: pointerLocator,
            brightness: brightness
        )
        diagnostics = collector.snapshot()
        refresh()
    }

    func refresh() {
        diagnostics = collector.snapshot()
        nsEventMouseLocation = NSEvent.mouseLocation
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 18) {
                systemStatus
                controls
                githubModule
            }
            .padding(20)

            Divider()
            HStack {
                Text(appVersionText)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button("Quit Bright Here") {
                    model.quit()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 540)
        .onAppear {
            model.refreshPermissionStatus()
        }
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

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "v\(version) (\(build))"
        }
        return "v\(version)"
    }

    private var systemStatus: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(systemStatusTint.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: systemStatusIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(systemStatusTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(systemStatusTitle)
                    .font(.headline)
                Text(systemStatusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !model.isAccessibilityTrusted {
                Button("Open Permissions") {
                    model.openAccessibilitySettings()
                }
            }
        }
        .padding(14)
        .background(systemStatusTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(systemStatusTint.opacity(0.38))
        )
    }

    private var systemStatusIsReady: Bool {
        model.isAccessibilityTrusted && model.isHotkeyListenerActive
    }

    private var systemStatusTitle: String {
        if systemStatusIsReady {
            return "All Set"
        }
        if !model.isAccessibilityTrusted {
            return "Permission Needed"
        }
        return "Listener Inactive"
    }

    private var systemStatusDetail: String {
        if systemStatusIsReady {
            return "Accessibility and F1/F2 listener are active."
        }
        if !model.isAccessibilityTrusted {
            return "Accessibility permission is required before F1/F2 can be routed."
        }
        return "Accessibility is granted, but the F1/F2 listener is not active."
    }

    private var systemStatusIcon: String {
        systemStatusIsReady ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    }

    private var systemStatusTint: Color {
        systemStatusIsReady ? .green : .orange
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Enable F1/F2 brightness routing", isOn: binding(\.isEnabled))
            Toggle("Show brightness overlay", isOn: binding(\.showBrightnessOverlay))
            Toggle("Launch at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Toggle("Show menu bar icon", isOn: Binding(
                get: { model.settings.showMenuBarIcon },
                set: { model.setShowMenuBarIcon($0) }
            ))

            HStack {
                Text("Step")
                Slider(value: Binding(
                    get: { Double(model.settings.brightnessStep) },
                    set: {
                        model.settings.brightnessStep = Float($0)
                        model.save()
                    }
                ), in: 0.005...0.08)
                Text(String(format: "%.1f%%", model.settings.brightnessStep * 100))
                    .frame(width: 50, alignment: .trailing)
                    .monospacedDigit()
            }

            #if DEBUG
            Button("Open Debug Panel") {
                model.openDebugWindow()
            }
            #endif
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

            HStack {
                Link("a1exsun/bright-here", destination: URL(string: "https://github.com/a1exsun/bright-here")!)
                Spacer()
                Button("It's not working") {
                    model.reportIssue()
                }
            }
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

struct DebugView: View {
    @ObservedObject var model: AppModel
    @StateObject var viewModel: DebugViewModel
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pointer Debug")
                        .font(.title3.weight(.semibold))
                    Text("Move the pointer across displays and confirm the selected display changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    viewModel.refresh()
                }
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    testControls
                    displayList
                }
                .padding(18)
            }
        }
        .frame(minWidth: 620, minHeight: 560)
        .onReceive(timer) { _ in
            viewModel.refresh()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("CG pointer", DiagnosticsFormatter.point(viewModel.diagnostics.pointerLocation))
            row("NSEvent pointer", DiagnosticsFormatter.point(viewModel.nsEventMouseLocation))
            row("Selected display", selectedDisplayText)
            row("Runtime", model.runtimeStatus)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var selectedDisplayText: String {
        guard let display = viewModel.diagnostics.selectedDisplay else {
            return "n/a"
        }
        return "#\(display.index) id=\(display.id) \(DiagnosticsFormatter.rect(display.bounds)) \(display.roleDescription)"
    }

    private var testControls: some View {
        HStack {
            Button("Test -") {
                model.testBrightness(.down)
                viewModel.refresh()
            }
            Button("Test +") {
                model.testBrightness(.up)
                viewModel.refresh()
            }
            Spacer()
            Text("Uses current CG pointer and native brightness API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Displays")
                .font(.headline)

            ForEach(viewModel.diagnostics.displays, id: \.display.id) { snapshot in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(snapshot.display.friendlyName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if snapshot.display.id == viewModel.diagnostics.selectedDisplay?.id {
                            Text("selected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    row("id", "\(snapshot.display.id)")
                    row("bounds", DiagnosticsFormatter.rect(snapshot.display.bounds))
                    row("brightness", DiagnosticsFormatter.brightness(snapshot.brightness))
                    row("contains CG pointer", snapshot.containsPointer ? "yes" : "no")
                    row("roles", snapshot.display.roleDescription.isEmpty ? "n/a" : snapshot.display.roleDescription)
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(snapshot.display.id == viewModel.diagnostics.selectedDisplay?.id ? .green : .secondary.opacity(0.25))
                )
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

let app = NSApplication.shared
let delegate = AppCoordinator()
app.delegate = delegate
app.run()
