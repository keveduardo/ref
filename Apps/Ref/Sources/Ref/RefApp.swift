import SwiftUI

/// The phone side of Ref: set the match up here, record it on the watch, read
/// the report here. P0 is the skeleton — the real screens arrive in P3; what
/// this proves is that the iOS target, RefKit and the watch embed all build
/// together. See SCOPE.md.
@main
struct RefApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = RenderDemo.page {
                RenderDemo(page: page)
            } else {
                RefScreen()
            }
            #else
            RefScreen()
            #endif
        }
    }
}

#if DEBUG
/// Each screen with fixed data, for screenshots from a simulator — launched as
/// `-renderDemo <page>` by the `render` job of ref.yml. Debug builds only.
struct RenderDemo: View {
    enum Page: String { case matches, setup, report, stats }

    static var page: Page? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderDemo"), i + 1 < args.count else { return nil }
        return Page(rawValue: args[i + 1])
    }

    let page: Page

    var body: some View {
        switch page {
        case .matches: RefScreen()
        case .setup: SetupPlaceholder()
        case .report: ReportPlaceholder()
        case .stats: StatsPlaceholder()
        }
    }
}
#endif
