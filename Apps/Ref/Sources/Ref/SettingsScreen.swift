import AuthenticationServices
import RefKit
import SwiftUI

/// The defaults a new match starts from. They also travel to the watch with
/// every assignment, for its quick start — the watch cannot read these keys
/// itself, since each device has its own `UserDefaults`.
struct SettingsScreen: View {
    let link: PhoneLink
    let account: AccountStore

    @State private var confirmingDelete = false
    @Environment(\.colorScheme) private var colorScheme

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
                accountSection
                Section("Watch") {
                    LabeledContent("Link", value: link.status)
                    if let error = link.lastSendError {
                        LabeledContent("Last send", value: error)
                            .foregroundStyle(.orange)
                    } else if let sent = link.lastSent {
                        LabeledContent("Last sent",
                                       value: "\(sent.formatted(date: .omitted, time: .shortened)) · \(link.lastSentCount) match\(link.lastSentCount == 1 ? "" : "es")")
                    }
                    Text("Upcoming matches and these defaults travel to the watch; finished matches come back here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// Optional: signed out, the app works fully and nothing leaves the phone.
    @ViewBuilder
    private var accountSection: some View {
        Section {
            if account.signedIn {
                LabeledContent("Signed in", value: account.email ?? "with Apple")
                if let last = account.lastSynced {
                    LabeledContent("Backed up", value: last.formatted(.relative(presentation: .named)))
                }
                Button {
                    Task { await account.sync() }
                } label: {
                    HStack {
                        Text("Back up now")
                        if account.syncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(account.syncing)
                Button("Sign out") { Task { await account.signOut() } }
                Button("Delete account", role: .destructive) { confirmingDelete = true }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    account.prepare(request)
                } onCompletion: { result in
                    Task { await account.complete(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
            }
            if let error = account.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Account")
        } footer: {
            Text(account.signedIn
                 ? "Matches and team sheets back up and sync to your other iPhones. Health numbers and routes stay on this phone."
                 : "Optional. Sign in to back up your matches and team sheets and keep them on a new iPhone. Health numbers and routes never leave this phone.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account and backup", role: .destructive) {
                Task { await account.deleteAccount() }
            }
        } message: {
            Text("Everything backed up is deleted now. Matches on this iPhone stay.")
        }
    }
}
