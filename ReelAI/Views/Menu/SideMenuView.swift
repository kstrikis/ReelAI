import SwiftUI

struct SideMenuView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Binding var isPresented: Bool
    @State private var showProfile = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                // Semi-transparent background
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isPresented = false
                        }
                    }

                // Menu content
                VStack(spacing: 0) {
                    // Header with user info
                    VStack(alignment: .leading, spacing: 12) {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white)
                                    .padding(15)
                            )

                        Text(authService.userProfile?.displayName ?? "No Name")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("@\(authService.userProfile?.username ?? "unknown")")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black)

                    // Menu items
                    ScrollView {
                        VStack(spacing: 0) {
                            MenuButton(
                                title: "Profile",
                                systemImage: "person.circle",
                                action: {
                                    showProfile = true
                                }
                            )

                            MenuButton(
                                title: "About",
                                systemImage: "info.circle",
                                action: {
                                    // TODO: Show about view
                                }
                            )

                            MenuButton(
                                title: "Settings",
                                systemImage: "gear",
                                action: {
                                    // TODO: Show settings
                                }
                            )

                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.vertical)

                            MenuButton(
                                title: "Sign Out",
                                systemImage: "rectangle.portrait.and.arrow.right",
                                action: {
                                    authService.signOut()
                                }
                            )
                        }
                        .padding(.vertical)
                    }
                }
                .frame(width: min(geometry.size.width * 0.8, 300))
                .background(Color(UIColor.systemBackground))
                .offset(x: isPresented ? 0 : geometry.size.width)
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
    }
}

// Helper view for menu buttons
private struct MenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 24)
                Text(title)
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.vertical, 12)
        })
    }
}

#if DEBUG
    struct SideMenuView_Previews: PreviewProvider {
        static var previews: some View {
            SideMenuView(isPresented: .constant(true))
                .environmentObject(AuthenticationService.preview)
        }
    }
#endif
