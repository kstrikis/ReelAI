import Combine
import SwiftUI

/// LoginView provides the main authentication interface for users
struct LoginView: View {
    // MARK: - Environment

    @EnvironmentObject private var authService: AuthenticationService

    // MARK: - State

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Store our subscriptions
    @StateObject private var subscriptions = CancellableStore()

    // MARK: - UI Constants

    private enum Constants {
        static let spacing: CGFloat = 20
        static let cornerRadius: CGFloat = 12
        static let buttonHeight: CGFloat = 50
        static let shadowRadius: CGFloat = 5
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background - TODO: Add video background later
            Color.black.ignoresSafeArea()

            // Content
            VStack(spacing: Constants.spacing) {
                Spacer()

                // Logo/Title
                Text("ReelAI")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Login Form
                VStack(spacing: Constants.spacing) {
                    // Email field
                    CustomTextField(
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalizeNone: true
                    )

                    // Password field
                    CustomTextField(
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        textContentType: .password,
                        autocapitalizeNone: true
                    )
                }
                .padding(.horizontal)

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                // Sign In Button
                Button(action: signIn, label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                })
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLoading || !isValidInput)

                // Demo Login Button
                Button(action: signInAsDemo, label: {
                    Text("Demo Login")
                        .fontWeight(.semibold)
                })
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLoading)

                // Sign Up Button
                Button(action: signUp, label: {
                    Text("Don't have an account? Sign Up")
                        .foregroundColor(.white)
                })
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLoading)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            Log.p(Log.auth, Log.start, "Login view appeared")
        }
        .onDisappear {
            Log.p(Log.auth, Log.exit, "Login view disappeared")
        }
    }

    // MARK: - Computed Properties

    private var isValidInput: Bool {
        !email.isEmpty && !password.isEmpty
    }

    // MARK: - Actions

    private func signIn() {
        Log.p(Log.auth, Log.start, "Starting email sign in")
        isLoading = true
        errorMessage = nil

        authService.signIn(email: email, password: password)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case let .failure(error) = completion {
                        errorMessage = error.localizedDescription
                        Log.p(Log.auth, Log.event, Log.error, "Sign in failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { _ in
                    Log.p(Log.auth, Log.event, Log.success, "Sign in successful")
                }
            )
            .store(in: subscriptions)
    }

    private func signInAsDemo() {
        Log.p(Log.auth, Log.start, "Starting demo sign in")
        isLoading = true
        errorMessage = nil

        authService.signInAsDemo()
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case let .failure(error) = completion {
                        errorMessage = error.localizedDescription
                        Log.p(Log.auth, Log.event, Log.error, "Demo sign in failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { _ in
                    Log.p(Log.auth, Log.event, Log.success, "Demo sign in successful")
                }
            )
            .store(in: subscriptions)
    }

    private func signUp() {
        Log.p(Log.auth, Log.start, "Attempting to access sign up")
        // TODO: Navigate to sign up view
        // For now, just show an alert that this is coming soon
        errorMessage = "Sign up coming soon!"
        Log.p(Log.auth, Log.event, Log.warning, "Sign up feature not yet implemented")
    }
}

// MARK: - Cancellable Store

final class CancellableStore: ObservableObject {
    private var storage = Set<AnyCancellable>()

    func store(_ cancellable: AnyCancellable) {
        storage.insert(cancellable)
    }
}

extension Cancellable {
    func store(in store: CancellableStore) {
        if let cancellable = self as? AnyCancellable {
            store.store(cancellable)
        } else {
            assertionFailure("Expected AnyCancellable but got \(type(of: self))")
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct LoginView_Previews: PreviewProvider {
        static var previews: some View {
            LoginView()
                .environmentObject(AuthenticationService.preview)
        }
    }
#endif
