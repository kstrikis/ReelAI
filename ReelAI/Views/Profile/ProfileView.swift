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
                // Force full width background
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SpaceBackground())
                    .ignoresSafeArea()
                
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
                    Button(action: { 
                        Log.p(Log.user, Log.event, "User dismissed profile view")
                        dismiss() 
                    }, label: {
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
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            Log.p(Log.user, Log.start, "Profile view appeared")
            setupInitialValues()
        }
        .onDisappear {
            Log.p(Log.user, Log.exit, "Profile view disappeared")
        }
    }

    private func setupInitialValues() {
        if let profile = authService.userProfile {
            Log.p(Log.user, Log.read, "Loading initial profile values")
            displayName = profile.displayName
            username = profile.username
        } else {
            Log.p(Log.user, Log.read, Log.warning, "No profile available to load")
        }
    }

    private func toggleEditMode() {
        withAnimation {
            if isEditing {
                Log.p(Log.user, Log.event, "User cancelled profile editing")
                // Reset values when canceling
                setupInitialValues()
            } else {
                Log.p(Log.user, Log.event, "User started profile editing")
            }
            isEditing.toggle()
            errorMessage = nil
        }
    }

    private func saveProfile() {
        Log.p(Log.user, Log.save, "Starting profile update")
        isLoading = true
        errorMessage = nil

        guard let userId = Auth.auth().currentUser?.uid else {
            Log.p(Log.user, Log.save, Log.error, "No authenticated user found")
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

        Log.p(Log.user, Log.save, "Updating profile for user: \(userId)")
        Log.p(Log.user, Log.save, "New display name: \(displayName)")
        Log.p(Log.user, Log.save, "New username: \(username)")

        // Update profile in Firestore
        FirestoreService.shared.updateUserProfile(updatedProfile, userId: userId)
            .timeout(10, scheduler: DispatchQueue.main) // Add timeout
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    
                    switch completion {
                    case .finished:
                        Log.p(Log.user, Log.save, Log.success, "Profile updated successfully")
                        // Update local profile immediately for better UX
                        authService.updateLocalProfile(updatedProfile)
                        isEditing = false
                        
                    case .failure(let error):
                        if (error as NSError).domain == NSPOSIXErrorDomain && (error as NSError).code == 50 {
                            Log.p(Log.user, Log.save, Log.error, "Network connection lost")
                            errorMessage = "Network connection lost. Please check your internet connection and try again."
                        } else {
                            Log.p(Log.user, Log.save, Log.error, "Failed to update profile: \(error.localizedDescription)")
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
