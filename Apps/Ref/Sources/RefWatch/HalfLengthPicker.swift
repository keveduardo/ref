import RefKit
import SwiftUI

/// "2 × 30 min" — a tap opens the picker. On the ready screen, at half time
/// and in the Record menu (Kevin, 2026-11-14: a beach-cup match set up as
/// 2 × 30 that was 2 × 25, and no way to change it on the wrist).
struct HalfLengthButton: View {
    let session: MatchSession
    @State private var picking = false

    var body: some View {
        if let setup = session.match?.setup {
            Button { picking = true } label: {
                Label("\(setup.clock.halves) × \(setup.halfMinutes) min", systemImage: "timer")
            }
            .font(.footnote)
            .accessibilityHint("Change the half length")
            .sheet(isPresented: $picking) {
                HalfLengthPicker(session: session, minutes: setup.halfMinutes)
            }
        }
    }
}

/// The Digital Crown turns the wheel; Done sets it.
struct HalfLengthPicker: View {
    let session: MatchSession
    @State var minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 4) {
            Text("Half length")
                .font(.headline)
            Picker("Minutes", selection: $minutes) {
                ForEach(MatchSetup.watchHalfMinutes, id: \.self) { m in
                    Text("\(m) min").tag(m)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Button("Done") {
                Haptics.play(.click)
                session.setHalfMinutes(minutes)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
