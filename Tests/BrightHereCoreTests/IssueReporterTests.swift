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
        #expect(query.first(where: { $0.name == "body" })?.value?.contains("Debug details") == true)
    }

    @Test("markdown includes pointer and log details")
    func markdownIncludesDiagnostics() {
        let markdown = IssueReporter.markdown(context: context())

        #expect(markdown.contains("Bright Here version: 0.1.0"))
        #expect(markdown.contains("Pointer location: 42.0, 24.0"))
        #expect(markdown.contains("display route failed"))
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
        recentLog: "display route failed"
    )
}
