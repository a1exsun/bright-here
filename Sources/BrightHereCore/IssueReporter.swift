import Foundation

public struct IssueReportContext: Equatable, Sendable {
    public let version: String
    public let macOSVersion: String
    public let permissionStatus: String
    public let runtimeStatus: String
    public let pointerDiagnostics: PointerDiagnostics
    public let recentLog: String

    public init(
        version: String,
        macOSVersion: String,
        permissionStatus: String,
        runtimeStatus: String,
        pointerDiagnostics: PointerDiagnostics,
        recentLog: String
    ) {
        self.version = version
        self.macOSVersion = macOSVersion
        self.permissionStatus = permissionStatus
        self.runtimeStatus = runtimeStatus
        self.pointerDiagnostics = pointerDiagnostics
        self.recentLog = recentLog
    }
}

public enum IssueReporter {
    public static let issueURLBase = URL(string: "https://github.com/a1exsun/bright-here/issues/new")!
    public static let defaultTitle = "Brightness does not follow pointer display"

    public static func issueURL(context: IssueReportContext) -> URL {
        var components = URLComponents(url: issueURLBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "title", value: defaultTitle),
            URLQueryItem(name: "body", value: shortBody(context: context))
        ]
        return components.url!
    }

    public static func shortBody(context: IssueReportContext) -> String {
        """
        ## What happened
        F1/F2 did not adjust the display under my pointer.

        ## Expected behavior
        Brightness should change on the display where the pointer is located.

        ## Debug details
        A full debug report was copied to my clipboard from Bright Here.
        """
    }

    public static func markdown(context: IssueReportContext) -> String {
        let selected = context.pointerDiagnostics.selectedDisplay.map { displayLine($0, brightness: nil, containsPointer: true) } ?? "n/a"
        let displays = context.pointerDiagnostics.displays.map {
            displayLine($0.display, brightness: $0.brightness, containsPointer: $0.containsPointer)
        }.joined(separator: "\n")

        return """
        ## What happened
        F1/F2 did not adjust the display under my pointer.

        ## Expected behavior
        Brightness should change on the display where the pointer is located.

        ## Environment
        - Bright Here version: \(context.version)
        - macOS version: \(context.macOSVersion)
        - Permission status: \(context.permissionStatus)
        - Runtime status: \(context.runtimeStatus)

        ## Pointer diagnostics
        - Pointer location: \(DiagnosticsFormatter.point(context.pointerDiagnostics.pointerLocation))
        - Selected display: \(selected)

        ## Displays
        \(displays.isEmpty ? "n/a" : displays)

        ## Recent logs
        ```text
        \(context.recentLog.isEmpty ? "n/a" : context.recentLog)
        ```

        ## Steps to reproduce
        1.
        2.
        3.
        """
    }

    private static func displayLine(_ display: ManagedDisplay, brightness: Float?, containsPointer: Bool) -> String {
        "- #\(display.index) id=\(display.id) bounds=\(DiagnosticsFormatter.rect(display.bounds)) brightness=\(DiagnosticsFormatter.brightness(brightness)) containsPointer=\(containsPointer) roles=\(display.roleDescription)"
    }
}
