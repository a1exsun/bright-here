import CoreGraphics
import Foundation
import Testing
@testable import BrightHereCore

@Suite("Issue reporter")
struct IssueReporterTests {
    @Test("builds GitHub issue URL with title and body")
    func buildsIssueURL() {
        let url = IssueReporter.issueURL(context: context())
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []

        #expect(url.absoluteString.hasPrefix("https://github.com/a1exsun/bright-here/issues/new?"))
        #expect(query.first(where: { $0.name == "title" })?.value == IssueReporter.defaultTitle)
        let body = query.first(where: { $0.name == "body" })?.value ?? ""
        #expect(body.contains("## Symptoms"))
        #expect(body.contains("> What did you see?"))
        #expect(body.contains("### Error Logs"))
        #expect(body.contains("> Bright Here copied environment details"))
        #expect(!body.contains("## Environment"))
    }

    @Test("clipboard text returns environment and only recent error logs")
    func clipboardTextReturnsEnvironmentAndErrorLogs() {
        let text = IssueReporter.clipboardText(context: context())

        #expect(text.hasPrefix("```text"))
        #expect(text.hasSuffix("```"))
        #expect(text.contains("Environment"))
        #expect(text.contains("Bright Here version: 0.1.0"))
        #expect(text.contains("Selected display: #1 id=7"))
        #expect(text.contains("Error Logs"))
        #expect(text.contains("display route failed"))
        #expect(!text.contains("normal startup"))
    }
}

private func context() -> IssueReportContext {
    let display = ManagedDisplay(
        index: 1,
        id: 7,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        isMain: true,
        isBuiltin: false,
        isActive: true,
        isOnline: true,
        isAsleep: false,
        source: "test"
    )

    return IssueReportContext(
        version: "0.1.0",
        macOSVersion: "Version 27.0",
        permissionStatus: "Ready",
        runtimeStatus: "Could not route brightness",
        pointerDiagnostics: PointerDiagnostics(
            pointerLocation: CGPoint(x: 42, y: 24),
            selectedDisplay: display,
            displays: [
                DisplaySnapshot(display: display, brightness: 0.5, containsPointer: true)
            ]
        ),
        recentErrorLog: """
        2026-06-15T00:00:00.000Z ERROR display route failed
        2026-06-15T00:00:01.000Z INFO normal startup
        """
    )
}
