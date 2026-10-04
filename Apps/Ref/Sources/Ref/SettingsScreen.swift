import RefKit
import SwiftUI

/// The defaults a new match starts from — the same keys the watch's
/// `SessionSettings` reads, so the two agree the moment they share a store
/// (the wire itself is P4).
struct SettingsScreen: View {
    let link: PhoneLink

    @AppStorage("ref.halfMinutes") private var halfMinutes = 45
    @AppStorage("ref.sinBinMinutes") private var sinBinMinutes = 10

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults") {
                    Picker("Half length", selection: $halfMinutes) {
                        ForEach([20, 25, 30, 35, 40, 45], id: \.self) { Text("\($0) minutes") }
                    }
                    Picker("Sin bin", selection: $sinBinMinutes) {
                        ForEach([5, 10, 15], id: \.self) { Text("\($0) minutes") }
                    }
                }
                Section("Watch") {
                    LabeledContent("Link", value: link.status)
                    Text("Assignments and finished matches travel over the link in P4.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
