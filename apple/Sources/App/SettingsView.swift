import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var apiKey = ""
    @State private var temperatureFeed = AppConfig.defaultTemperatureFeed
    @State private var humidityFeed = AppConfig.defaultHumidityFeed

    var body: some View {
        NavigationStack {
            Form {
                Section("Adafruit IO") {
                    TextField("Brukernavn", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("AIO-nøkkel (aio_…)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Feeds") {
                    TextField("Temperatur-feed", text: $temperatureFeed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Fuktighet-feed", text: $humidityFeed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Nøkkelen lagres i Keychain og deles med klokke-komplikasjonen via App Group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Innstillinger")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") { save() }
                        .disabled(username.isEmpty || apiKey.isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let creds = CredentialStore.load() else { return }
        username = creds.username
        apiKey = creds.apiKey
        temperatureFeed = creds.temperatureFeed
        humidityFeed = creds.humidityFeed
    }

    private func save() {
        CredentialStore.save(Credentials(
            username: username.trimmingCharacters(in: .whitespaces),
            apiKey: apiKey.trimmingCharacters(in: .whitespaces),
            temperatureFeed: temperatureFeed.trimmingCharacters(in: .whitespaces),
            humidityFeed: humidityFeed.trimmingCharacters(in: .whitespaces)
        ))
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

#Preview {
    SettingsView()
}
