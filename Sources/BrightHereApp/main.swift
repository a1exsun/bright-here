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
    private var contentView: BrightnessOverlayContentView?
    private var hideTimer: Timer?
    private var isEditing = false
    private var isHovering = false

    private var isInteractive: Bool {
        isEditing || isHovering
    }

    func show(
        level: BrightnessIndicatorState,
        on display: ManagedDisplay,
        onValueChange: @escaping (Float) -> Void
    ) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let contentView = self.contentView ?? BrightnessOverlayContentView(frame: NSRect(
            origin: .zero,
            size: BrightnessOverlayContentView.preferredSize
        ))
        contentView.configure(
            level: level,
            displayName: display.friendlyName,
            onValueChange: onValueChange,
            onEditingChanged: { [weak self] isEditing in
                self?.isEditing = isEditing
                if isEditing {
                    self?.hideTimer?.invalidate()
                } else {
                    self?.scheduleHideIfNeeded()
                }
            },
            onHoverChanged: { [weak self] isHovering in
                self?.isHovering = isHovering
                if isHovering {
                    self?.hideTimer?.invalidate()
                } else {
                    self?.scheduleHideIfNeeded()
                }
            }
        )
        panel.contentView = contentView
        self.contentView = contentView

        position(panel, on: Self.screen(for: display) ?? NSScreen.main)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        contentView.syncHoverStateWithMouseLocation()
        scheduleHideIfNeeded()
    }

    private func makePanel() -> BrightnessOverlayPanel {
        BrightnessOverlayPanel(contentRect: NSRect(
            origin: .zero,
            size: BrightnessOverlayContentView.preferredSize
        ))
    }

    private func scheduleHideIfNeeded() {
        guard !isInteractive else {
            return
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
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

    private func hideImmediately() {
        hideTimer?.invalidate()
        isEditing = false
        isHovering = false
        contentView?.resetHoverState()
        panel?.orderOut(nil)
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - size.width - 48,
            y: frame.maxY - size.height - 10
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

@MainActor
final class BrightnessOverlayContentView: NSView {
    static let preferredSize = NSSize(width: 290, height: 62)

    private let cardView: NSView
    private let contentHost: NSView
    private let usesGlassEffect: Bool
    private let cornerRadius: CGFloat = 26
    private let titleLabel = NSTextField(labelWithString: "")
    private let slider = BrightnessOverlaySlider(frame: .zero)
    private var trackingArea: NSTrackingArea?
    private var onValueChange: ((Float) -> Void)?
    private var onEditingChanged: ((Bool) -> Void)?
    private var onHoverChanged: ((Bool) -> Void)?
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *), let glass = Self.makeGlassEffectView(contentView: host, cornerRadius: cornerRadius) {
            cardView = glass
            usesGlassEffect = true
        } else {
            let visual = NSVisualEffectView()
            visual.material = .hudWindow
            visual.blendingMode = .behindWindow
            visual.state = .active
            visual.addSubview(host)
            cardView = visual
            usesGlassEffect = false
        }

        contentHost = host
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private static func makeGlassEffectView(contentView: NSView, cornerRadius: CGFloat) -> NSView? {
        guard let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            return nil
        }

        let glass = glassClass.init(frame: .zero)
        glass.setValue(contentView, forKey: "contentView")
        glass.setValue(cornerRadius, forKey: "cornerRadius")
        return glass
    }

    func configure(
        level: BrightnessIndicatorState,
        displayName: String,
        onValueChange: @escaping (Float) -> Void,
        onEditingChanged: @escaping (Bool) -> Void,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        titleLabel.stringValue = displayName
        slider.doubleValue = Double(level.normalizedValue)
        self.onValueChange = onValueChange
        self.onEditingChanged = onEditingChanged
        self.onHoverChanged = onHoverChanged
    }

    func resetHoverState() {
        isHovering = false
        slider.showsKnob = false
    }

    func syncHoverStateWithMouseLocation() {
        guard let window else {
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovering(bounds.contains(location))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    private func setupView() {
        setupCard()
        setupContent()
    }

    private func setupCard() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        if !usesGlassEffect {
            cardView.wantsLayer = true
            cardView.layer?.cornerRadius = cornerRadius
            cardView.layer?.cornerCurve = .continuous
            cardView.layer?.masksToBounds = true
        }
        addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        if contentHost.superview == cardView {
            NSLayoutConstraint.activate([
                contentHost.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                contentHost.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                contentHost.topAnchor.constraint(equalTo: cardView.topAnchor),
                contentHost.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
            ])
        }
    }

    private func setupContent() {
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let minimumIcon = iconView(symbolName: "sun.min.fill", pointSize: 12)
        let maximumIcon = iconView(symbolName: "sun.max.fill", pointSize: 13)

        slider.controlSize = .small
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.trackFillColor = .white
        slider.showsKnob = false
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.onEditingChanged = { [weak self] editing in
            self?.onEditingChanged?(editing)
        }
        slider.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [minimumIcon, slider, maximumIcon])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(stack)

        NSLayoutConstraint.activate([
            minimumIcon.widthAnchor.constraint(equalToConstant: 15),
            maximumIcon.widthAnchor.constraint(equalToConstant: 17),
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 166),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor, constant: -15),
            stack.centerYAnchor.constraint(equalTo: contentHost.centerYAnchor)
        ])
    }

    private func iconView(symbolName: String, pointSize: CGFloat) -> NSImageView {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true

        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = .labelColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else {
            return
        }

        isHovering = hovering
        slider.showsKnob = hovering
        onHoverChanged?(hovering)
    }

    @objc private func sliderChanged() {
        onValueChange?(Float(slider.doubleValue))
    }
}

@MainActor
final class BrightnessOverlaySlider: NSSlider {
    var onEditingChanged: ((Bool) -> Void)?
    var showsKnob = true {
        didSet {
            guard oldValue != showsKnob else {
                return
            }
            (cell as? BrightnessOverlaySliderCell)?.showsKnob = showsKnob
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installCell()
    }

    override func mouseDown(with event: NSEvent) {
        onEditingChanged?(true)
        super.mouseDown(with: event)
        onEditingChanged?(false)
    }

    private func installCell() {
        let sliderCell = BrightnessOverlaySliderCell()
        sliderCell.minValue = minValue
        sliderCell.maxValue = maxValue
        sliderCell.doubleValue = doubleValue
        sliderCell.isContinuous = isContinuous
        sliderCell.controlSize = controlSize
        sliderCell.showsKnob = showsKnob
        cell = sliderCell
    }
}

final class BrightnessOverlaySliderCell: NSSliderCell {
    var showsKnob = true

    override func drawKnob(_ knobRect: NSRect) {
        guard showsKnob else {
            return
        }
        super.drawKnob(knobRect)
    }

    override func drawKnob() {
        guard showsKnob else {
            return
        }
        super.drawKnob()
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 18) {
                if !model.isAccessibilityTrusted {
                    systemStatus
                }
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
            Image(nsImage: settingsLogoImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Bright Here")
                    .font(.title3.weight(.semibold))
                Text("Your brightness follows your cursor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var settingsLogoImage: NSImage {
        if colorScheme == .dark, let image = NSImage(named: "AppIconDark") {
            return image
        }
        return NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
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

    private var systemStatusTitle: String {
        "Permission Needed"
    }

    private var systemStatusDetail: String {
        "Accessibility permission is required before F1/F2 can be routed."
    }

    private var systemStatusIcon: String {
        "exclamationmark.triangle.fill"
    }

    private var systemStatusTint: Color {
        .orange
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            #if DEBUG || LOCAL_DEBUG_PANEL
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
