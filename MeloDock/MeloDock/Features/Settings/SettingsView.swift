import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("General") {
                Picker("Preferred Provider", selection: $viewModel.preferredProvider) {
                    ForEach(MusicProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Toggle("Show island", isOn: $viewModel.showOnStartup)
                Button("Show/Hide Overlay Now") {
                    NotificationCenter.default.post(name: .meloDockToggleOverlay, object: nil)
                }
                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                Text("Login Item Status: \(viewModel.launchAtLoginStatusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Island") {
                Toggle("Power and battery", isOn: $viewModel.showPower)
                Toggle("Audio and Bluetooth", isOn: $viewModel.showAudio)
                Toggle("Microphone in use", isOn: $viewModel.showCapture)
                Toggle("Timer", isOn: $viewModel.showTimer)
                Toggle("Calendar", isOn: Binding(
                    get: { viewModel.showCalendar },
                    set: { enabled in Task { await viewModel.setCalendarEnabled(enabled) } }
                ))
                if viewModel.calendarAccessDenied {
                    Text("Calendar access is turned off for MeloDock.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Open System Settings") {
                        viewModel.openCalendarPrivacySettings()
                    }
                }
            }

            Section("Apple Music") {
                providerStatusRow(viewModel.appleMusicAuthState)
                Button("Connect Apple Music") {
                    viewModel.authorizeAppleMusic()
                }
            }

            Section("Spotify") {
                providerStatusRow(viewModel.spotifyAuthState)
                TextField("Spotify Client ID", text: $viewModel.spotifyClientID)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Connect Spotify") { viewModel.authorizeSpotify() }
                    Button("Clear Spotify Session") { viewModel.clearSpotifySession() }
                }
                Text("Set redirect URI to `melodock://spotify-auth` in Spotify Developer Dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                Text("Current global hotkey: \(viewModel.hotkeyDescription)")
                Text("Tip: Press \(viewModel.hotkeyDescription) to show/hide overlay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Toggle Overlay Now") {
                    NotificationCenter.default.post(name: .meloDockToggleOverlay, object: nil)
                }
                Button("Reset to Option+Command+M") {
                    viewModel.resetHotkey()
                }
            }

            Section("Pro (StoreKit 2 Ready)") {
                Text(viewModel.isProUnlocked ? "Pro unlocked." : "Free tier active.")
                Button("Refresh Purchase Status") {
                    viewModel.refreshProStatus()
                }
            }

            if let infoText = viewModel.statusInfoText {
                Section("Info") {
                    Text(infoText)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText = viewModel.errorText {
                Section("Status") {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 560)
        .onAppear { viewModel.refreshCalendarAccess() }
    }

    @ViewBuilder
    private func providerStatusRow(_ state: ProviderAuthState) -> some View {
        switch state {
        case .authorized:
            Label("Connected", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .unauthorized:
            Label("Not connected", systemImage: "xmark.seal")
                .foregroundStyle(.orange)
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle")
        case .unavailable(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
