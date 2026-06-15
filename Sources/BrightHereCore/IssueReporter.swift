import Foundation

public struct IssueReportContext: Equatable, Sendable {
    public let version: String
    public let macOSVersion: String
    public let permissionStatus: String
    public let runtimeStatus: String
    public let pointerDiagnostics: PointerDiagnostics
    public let recentErrorLog: String

    public init(
        version: String,
        macOSVersion: String,
        permissionStatus: String,
        runtimeStatus: String,
        pointerDiagnostics: PointerDiagnostics,
        recentErrorLog: String
    ) {
        self.version = version
        self.macOSVersion = macOSVersion
        self.permissionStatus = permissionStatus
        self.runtimeStatus = runtimeStatus
        self.pointerDiagnostics = pointerDiagnostics
        self.recentErrorLog = recentErrorLog
    }
}

public enum IssueReporter {
    public static let issueURLBase = URL(string: "https://github.com/a1exsun/bright-here/issues/new")!
    public static let defaultTitle = "Bug report: "

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
        ## Defect title
        > Replace this with a short title.

        ## Symptoms
        > What did you see? What did not work?

        ## Expected behavior
        > What did you expect Bright Here to do?

        ## Steps to reproduce
        > 1.
        > 2.
        > 3.

        ### Error Logs
        > Bright Here copied environment details and recent ERROR log lines to your clipboard. Paste them below if available.
        """
    }

    public static func clipboardText(context: IssueReportContext) -> String {
        let errors = context.recentErrorLog
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains(" ERROR ") || $0.hasPrefix("ERROR ") }
            .joined(separator: "\n")
        let errorText = errors.isEmpty ? "No recent ERROR log lines found." : errors

        return """
        ```text
        Environment
        - Bright Here version: \(context.version)
        - macOS version: \(context.macOSVersion)
        - Permission status: \(context.permissionStatus)
        - Runtime status: \(context.runtimeStatus)
        - Pointer location: \(DiagnosticsFormatter.point(context.pointerDiagnostics.pointerLocation))
        - Selected display: \(selectedDisplaySummary(context.pointerDiagnostics.selectedDisplay))

        Error Logs
        \(errorText)
        ```
        """
    }

    private static func selectedDisplaySummary(_ display: ManagedDisplay?) -> String {
        guard let display else {
            return "n/a"
        }
        return "#\(display.index) id=\(display.id) bounds=\(DiagnosticsFormatter.rect(display.bounds)) roles=\(display.roleDescription)"
    }
}
