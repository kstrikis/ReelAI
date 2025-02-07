import SwiftUI

struct SideMenuView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Binding var isPresented: Bool
    @State private var showProfile = false
    @State private var showDebugMenu = false
    @State private var stars: [(position: CGPoint, opacity: Double)] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // Semi-transparent background
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            Log.p(Log.app, Log.event, "User tapped to dismiss side menu")
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
                    .background(Color.black.opacity(0.7))

                    // Menu items
                    ScrollView {
                        VStack(spacing: 0) {
                            MenuButton(
                                title: "Profile",
                                systemImage: "person.circle",
                                action: {
                                    Log.p(Log.app, Log.event, "User selected Profile menu item")
                                    showProfile = true
                                }
                            )

                            MenuButton(
                                title: "About",
                                systemImage: "info.circle",
                                action: {
                                    Log.p(Log.app, Log.event, "User selected About menu item")
                                    // TODO: Show about view
                                }
                            )

                            MenuButton(
                                title: "Settings",
                                systemImage: "gear",
                                action: {
                                    Log.p(Log.app, Log.event, "User selected Settings menu item")
                                    // TODO: Show settings
                                }
                            )

                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.vertical)

                            #if DEBUG
                            Group {
                                MenuButton(
                                    title: "Debug Tools",
                                    systemImage: "hammer.fill",
                                    action: {
                                        Log.p(Log.app, Log.event, "User selected Debug Tools menu item")
                                        showDebugMenu = true
                                    }
                                )
                                
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.vertical)
                            }
                            #endif

                            MenuButton(
                                title: "Sign Out",
                                systemImage: "rectangle.portrait.and.arrow.right",
                                action: {
                                    Log.p(Log.auth, Log.start, "User initiated sign out")
                                    authService.signOut()
                                }
                            )
                        }
                        .padding(.vertical)
                    }
                }
                .frame(width: min(geometry.size.width * 0.8, 300))
                .background(
                    ZStack {
                        Color.black
                        // Starfield effect
                        ForEach(0..<stars.count, id: \.self) { index in
                            Circle()
                                .fill(Color.white)
                                .frame(width: 2, height: 2)
                                .position(stars[index].position)
                                .opacity(stars[index].opacity)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(radius: 10)
                .offset(x: isPresented ? 0 : geometry.size.width)
                .offset(y: geometry.safeAreaInsets.top)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            NavigationView {
                DebugMenuView()
            }
        }
        #endif
        .onAppear {
            Log.p(Log.app, Log.start, "Side menu appeared")
            generateStars()
        }
        .onDisappear {
            Log.p(Log.app, Log.exit, "Side menu disappeared")
        }
    }
    
    private func generateStars() {
        stars = (0..<100).map { _ in
            (
                position: CGPoint(
                    x: CGFloat.random(in: 0...300),
                    y: CGFloat.random(in: 0...800)
                ),
                opacity: Double.random(in: 0.1...0.8)
            )
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
            .padding(.horizontal)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        })
        .buttonStyle(PlainButtonStyle())
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
