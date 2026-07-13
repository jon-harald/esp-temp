import SwiftUI

struct AccountView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    LabeledContent("E-post", value: auth.email ?? "–")
                }
                Section {
                    Button("Logg ut", role: .destructive) {
                        Task {
                            await auth.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Konto")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
    }
}
