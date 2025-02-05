import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var displayName = ""
    @State private var username = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Profile Image (placeholder for now)
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white)
                                    .padding(25)
                            )
                            .padding(.top, 20)

                        if isEditing {
                            // Edit Mode
                            VStack(spacing: 15) {
                                CustomTextField(
                                    placeholder: "Display Name",
                                    text: $displayName
                                )

                                CustomTextField(
                                    placeholder: "Username",
                                    text: $username,
                                    autocapitalizeNone: true
                                )

                                if let errorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }

                                Button(action: saveProfile, label: {
                                    if isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("Save Changes")
                                            .fontWeight(.semibold)
                                    }
                                })
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(isLoading)
                            }
                            .padding(.horizontal)
                        } else {
                            // View Mode
                            VStack(spacing: 10) {
                                Text(authService.userProfile?.displayName ?? "No Name")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text("@\(authService.userProfile?.username ?? "unknown")")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)

                                if let email = authService.userProfile?.email {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }, label: {
                        Text("Done")
                            .foregroundColor(.white)
                    })
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: toggleEditMode, label: {
                        Text(isEditing ? "Cancel" : "Edit")
                            .foregroundColor(.white)
                    })
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear(perform: setupInitialValues)
    }

    private func setupInitialValues() {
        if let profile = authService.userProfile {
            displayName = profile.displayName
            username = profile.username
        }
    }

    private func toggleEditMode() {
        withAnimation {
            if isEditing {
                // Reset values when canceling
                setupInitialValues()
            }
            isEditing.toggle()
            errorMessage = nil
        }
    }

    private func saveProfile() {
        AppLogger.dbEntry("Starting profile update", collection: "users")
        isLoading = true
        errorMessage = nil

        guard let userId = Auth.auth().currentUser?.uid else {
            AppLogger.dbError("No authenticated user found", error: NSError(), collection: "users")
            errorMessage = "Not authenticated"
            isLoading = false
            return
        }

        // Create new profile with updated values
        let updatedProfile = UserProfile(
            username: username,
            displayName: displayName,
            email: authService.userProfile?.email,
            profileImageUrl: authService.userProfile?.profileImageUrl,
            createdAt: authService.userProfile?.createdAt ?? Date()
        )

        // Update profile in Firestore
        FirestoreService.shared.updateUserProfile(updatedProfile, userId: userId)
            .timeout(10, scheduler: DispatchQueue.main) // Add timeout
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    
                    switch completion {
                    case .finished:
                        AppLogger.dbSuccess("Profile updated successfully", collection: "users")
                        // Update local profile immediately for better UX
                        authService.updateLocalProfile(updatedProfile)
                        isEditing = false
                        
                    case .failure(let error):
                        AppLogger.dbError("Failed to update profile", error: error, collection: "users")
                        if (error as NSError).domain == NSPOSIXErrorDomain && (error as NSError).code == 50 {
                            errorMessage = "Network connection lost. Please check your internet connection and try again."
                        } else {
                            errorMessage = "Failed to update profile: \(error.localizedDescription)"
                        }
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &authService.cancellables)
    }
}

#if DEBUG
    struct ProfileView_Previews: PreviewProvider {
        static var previews: some View {
            ProfileView()
                .environmentObject(AuthenticationService.preview)
        }
    }
#endif
