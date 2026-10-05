import SwiftUI

/// Ref on the wrist: the clock, the score, the cards — recorded here, with the
/// phone in the bag. See SCOPE.md.
@main
struct RefWatchApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = RenderDemo.page {
                RenderDemo(page: page)
            } else {
                RootScreen()
            }
            #else
            RootScreen()
            #endif
        }
    }
}

/// One place decides what the watch is showing; the session decides the rest.
struct RootScreen: View {
    @State private var session = MatchSession()

    var body: some View {
        switch session.stage {
        case .home:
            StartScreen(session: session)
        case .ready, .live:
            LiveScreen(session: session)
        case .halfTime:
            HalfTimeScreen(session: session)
        case .summary:
            SummaryScreen(session: session)
        }
    }
}

#if DEBUG
/// Each screen with fixed data, for screenshots from a watch simulator —
/// launched as `-renderDemo <page>` by the `render` job of ref.yml. Debug
/// builds only.
struct RenderDemo: View {
    enum Page: String { case start, live, home, record, number, halftime, summary }

    static var page: Page? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderDemo"), i + 1 < args.count else { return nil }
        return Page(rawValue: args[i + 1])
    }

    let page: Page

    var body: some View {
        switch page {
        case .start:
            StartScreen(session: .showing("start"), requestsAccess: false)
        case .live:
            LiveScreen(session: .showing("live"))
        case .home:
            // The page a swipe right reaches mid-match.
            RecordFlow(session: .showing("live"), side: .home, onDone: {})
        case .record:
            RecordFlow(session: .showing("live"))
        case .number:
            // The keypad must fit one screen on every watch — this shows it.
            // Inside a navigation stack, as RecordFlow presents it — so the
            // header sits below the clock, as on the wrist.
            NavigationStack {
                PlayerPicker(squad: nil, allowNone: true, title: "Goal · ARS", pick: { _ in })
            }
        case .halftime:
            HalfTimeScreen(session: .showing("halftime"))
        case .summary:
            SummaryScreen(session: .showing("summary"))
        }
    }
}
#endif
