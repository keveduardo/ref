import SwiftUI

/// Ref on the wrist: the clock, the score, the cards — recorded here, with the
/// phone in the bag. P0 is the skeleton; the live screens are P2. See SCOPE.md.
@main
struct RefWatchApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = RenderDemo.page {
                RenderDemo(page: page)
            } else {
                LiveScreen()
            }
            #else
            LiveScreen()
            #endif
        }
    }
}

#if DEBUG
/// Each screen with fixed data, for screenshots from a watch simulator —
/// launched as `-renderDemo <page>` by the `render` job of ref.yml. Debug
/// builds only.
struct RenderDemo: View {
    enum Page: String { case start, live }

    static var page: Page? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderDemo"), i + 1 < args.count else { return nil }
        return Page(rawValue: args[i + 1])
    }

    let page: Page

    var body: some View {
        switch page {
        case .start: StartScreen()
        case .live: LiveScreen()
        }
    }
}
#endif
