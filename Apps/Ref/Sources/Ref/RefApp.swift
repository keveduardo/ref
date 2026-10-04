import RefKit
import SwiftUI

/// The phone side of Ref: set the match up here, record it on the watch, read
/// the report here. See SCOPE.md.
@main
struct RefApp: App {
    @State private var store: PhoneStore
    @State private var link: PhoneLink

    init() {
        // ! Wired here, not in a view's `.task`: WatchConnectivity can wake
        // the app in the background to hand over a finished match, before any
        // view exists — and a `transferUserInfo` handed to a nil handler is
        // gone for good.
        let store = PhoneStore()
        _store = State(initialValue: store)
        _link = State(initialValue: PhoneLink(onFinished: { match in store.save(match) },
                                              onRoute: { store.routesChanged() }))
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = RenderDemo.page {
                RenderDemo(page: page)
            } else {
                RefScreen(store: store, link: link)
            }
            #else
            RefScreen(store: store, link: link)
            #endif
        }
    }
}

#if DEBUG
/// Each screen with seeded data, for screenshots from a simulator — launched
/// as `-renderDemo <page>` by the `render` job of ref.yml. Debug builds only.
struct RenderDemo: View {
    enum Page: String { case matches, setup, teams, detail, stats, settings }

    static var page: Page? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderDemo"), i + 1 < args.count else { return nil }
        return Page(rawValue: args[i + 1])
    }

    let page: Page

    var body: some View {
        switch page {
        case .matches:
            RefScreen(store: .demo(), link: PhoneLink())
        case .setup:
            MatchSetupScreen(store: .demo())
        case .teams:
            TeamsScreen(store: .demo())
        case .detail:
            MatchDetailDemo()
        case .stats:
            StatsScreen(store: .demo())
        case .settings:
            SettingsScreen(link: PhoneLink())
        }
    }
}

/// The detail page needs a match with a history, so this builds the demo
/// store first and picks the played one out of it.
struct MatchDetailDemo: View {
    var body: some View {
        let store = PhoneStore.demo()
        NavigationStack {
            if let match = store.played.first {
                MatchDetailScreen(store: store, match: match)
            }
        }
    }
}
#endif
