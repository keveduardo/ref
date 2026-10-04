import RefKit
import SwiftUI

/// "Mark field": stand on the centre spot, face either goal, tap. The watch
/// keeps where it is and which way it points, and the phone draws the pitch
/// diagram in that frame. Optional — without it, the phone works the field
/// out from the route.
struct MarkFieldScreen: View {
    let session: MatchSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Stand on the centre spot and face either goal.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                status
                Button("Mark") {
                    if session.markField() {
                        Haptics.recorded()
                        dismiss()
                    } else {
                        Haptics.play(.failure)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ready)
                Button("Cancel") { dismiss() }
                    .font(.footnote)
            }
        }
        .onAppear { session.location.warmUp() }
    }

    private var ready: Bool {
        guard let fix = session.location.latestFix else { return false }
        return fix.accuracy > 0 && fix.accuracy <= 20
            && (session.location.latestHeading != nil || !session.location.compassAvailable)
    }

    @ViewBuilder
    private var status: some View {
        if let fix = session.location.latestFix, fix.accuracy > 0, fix.accuracy <= 20 {
            if let heading = session.location.latestHeading {
                Label("GPS ±\(Int(fix.accuracy)) m · facing \(Int(heading))°", systemImage: "location.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else if !session.location.compassAvailable {
                Text("No compass on this watch — the phone will work out the field's direction.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Finding the compass…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            Text("Finding GPS…").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
