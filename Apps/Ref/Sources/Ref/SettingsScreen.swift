import RefKit
import SwiftUI

/// The defaults a new match starts from. They also travel to the watch with
/// every assignment, for its quick start — the watch cannot read these keys
/// itself, since each device has its own `UserDefaults`.
struct SettingsScreen: View {
    let link: PhoneLink

    @AppStorage("ref.halfMinutes") private var halfMinutes = 45
    @AppStorage("ref.halfTimeMinutes") private var halfTimeMinutes = MatchDefaults.standard.halfTimeMinutes
    @AppStorage("ref.addedTimeButton") private var addedTimeButton = false
    @AppStorage("ref.quarterBreak") private var quarterBreak = false
    @AppStorage("ref.quarterBreakMinutes") private var quarterBreakMinutes = 2

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults") {
                    Picker("Half length", selection: $halfMinutes) {
                        ForEach([20, 25, 30, 35, 40, 45], id: \.self) { Text("\($0) minutes") }
                    }
                    Picker("Half-time", selection: $halfTimeMinutes) {
                        ForEach(1...15, id: \.self) { Text("\($0) minutes") }
                    }
                    Toggle("Added time button", isOn: $addedTimeButton)
                    Toggle("Quarter breaks", isOn: $quarterBreak)
                    if quarterBreak {
                        Picker("Break length", selection: $quarterBreakMinutes) {
                            ForEach(1...10, id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                }
                Section("Watch") {
                    LabeledContent("Link", value: link.status)
                    Text("Upcoming matches and these defaults travel to the watch; finished matches come back here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
