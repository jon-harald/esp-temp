import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Logg inn for å sette varslingsgrenser og motta push når temperaturen går utenfor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SignInWithAppleButton(.signIn) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await auth.handleSignInWithApple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .listRowInsets(EdgeInsets())
                }

                Section(isSignUp ? "Ny konto" : "E-post") {
                    TextField("E-post", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passord", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)

                    Button(isSignUp ? "Opprett konto" : "Logg inn") {
                        Task {
                            if isSignUp {
                                await auth.signUp(email: email, password: password)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    }
                    .disabled(email.isEmpty || password.count < 6)

                    Button(isSignUp ? "Har du konto? Logg inn" : "Ny bruker? Opprett konto") {
                        isSignUp.toggle()
                    }
                    .font(.footnote)
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Logg inn")
        }
    }
}
