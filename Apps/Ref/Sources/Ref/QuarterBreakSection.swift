import RefKit
import SwiftUI

/// The quarter-break settings, shared by New Match and Edit: a switch, when
/// in each half it falls (midway unless a minute is picked), and how long it
/// lasts. The watch stops the clock for it and buzzes at both ends.
struct QuarterBreakSection: View {
    @Binding var quarterBreak: QuarterBreak?
    let halfMinutes: Int

    var body: some View {
        Section {
            Toggle("Quarter breaks", isOn: Binding(
                get: { quarterBreak != nil },
                set: { quarterBreak = $0 ? QuarterBreak(breakMinutes: QuarterBreakDefaults.breakMinutes) : nil }))
            if let current = quarterBreak {
                Picker("Quarter at", selection: Binding(
                    get: { current.atMinute ?? 0 },
                    set: { quarterBreak?.atMinute = $0 == 0 ? nil : $0 })) {
                    Text("Midway (\(halfMinutes / 2) min)").tag(0)
                    ForEach(Array(stride(from: 5, to: max(6, halfMinutes), by: 1)), id: \.self) {
                        Text("\($0) min").tag($0)
                    }
                }
                Picker("Break length", selection: Binding(
                    get: { current.breakMinutes },
                    set: { quarterBreak?.breakMinutes = $0 })) {
                    ForEach(1...10, id: \.self) { Text("\($0) min").tag($0) }
                }
            }
        } header: {
            Text("Quarter breaks")
        } footer: {
            if quarterBreak != nil {
                Text("The watch buzzes at the quarter mark of each half. Tap Quarter break to stop the clock; it buzzes again when the break is up, and Resume starts the clock.")
            }
        }
    }
}

/// The defaults in Settings, read where a new match is made.
enum QuarterBreakDefaults {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "ref.quarterBreak") }
    static var breakMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "ref.quarterBreakMinutes")
        return stored == 0 ? 2 : stored
    }
    static var value: QuarterBreak? { enabled ? QuarterBreak(breakMinutes: breakMinutes) : nil }
}
