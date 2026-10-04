import RefKit
import SwiftUI
import WatchKit

/// The watch's home: start today's match. The phone's assignment (P4) will
/// appear above the quick start; for now the quick start is the way in.
struct StartScreen: View {
    let session: MatchSession

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "soccerball")
            Button {
                Haptics.play(.start)
                session.startQuick()
            } label: {
                Text("Quick start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("Two teams, \(SessionSettings.halfMinutes)-minute halves. Rename them on the phone afterwards.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
