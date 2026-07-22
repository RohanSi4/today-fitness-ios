import SwiftUI

struct CoachSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: CoachSyncService
    @ObservedObject var store: TodayStore

    @State private var pairingCode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: service.state.symbol)
                            .font(.title2)
                            .foregroundStyle(statusColor)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(service.state.title).font(.headline)
                            Text(statusDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Coach connection")
                }

                if service.isConnected {
                    Section {
                        Button {
                            Task { await store.syncWithCoach() }
                        } label: {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(service.state == .syncing)

                        Button("Disconnect", role: .destructive) {
                            service.disconnect()
                        }
                    } footer: {
                        Text("Today keeps working offline. A failed sync never blocks weight or workout logging.")
                    }
                } else {
                    Section {
                        TextField("Paste connection code", text: $pairingCode, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                            .lineLimit(3...6)

                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red)
                        }

                        Button("Connect to coach") {
                            connect()
                        }
                        .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("One-time setup")
                    } footer: {
                        Text("Generate the code from the private coach repo. The encryption key is stored in this phone's Keychain.")
                    }
                }

                Section("What syncs") {
                    Label("Morning weight and weight trend", systemImage: "scalemass")
                    Label("Finished exercises, sets, reps, and load", systemImage: "dumbbell")
                    Label("A small strength summary for the public fitness page", systemImage: "chart.bar")
                }

                Section {
                    Text("The private snapshot is encrypted before it leaves this phone. The website stores the sealed data, and only the coach has the key that opens it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Coach sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .synced: .green
        case .failed: .orange
        default: TodayPalette.accent
        }
    }

    private var statusDetail: String {
        switch service.state {
        case .notConnected:
            "Pair once to keep the coach current."
        case .ready:
            "There are changes waiting to upload."
        case .syncing:
            "Encrypting and sending the latest snapshot."
        case .synced(let date):
            "Last synced \(date.formatted(.relative(presentation: .named)))."
        case .failed(let message):
            message
        }
    }

    private func connect() {
        do {
            try service.connect(pairingCode: pairingCode)
            pairingCode = ""
            errorMessage = nil
            Task { await store.syncWithCoach() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
