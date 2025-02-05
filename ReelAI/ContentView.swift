//
//  ContentView.swift
//  ReelAI
//
//  Created by Kriss on 2/3/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var selectedTab = 1 // 0: Camera, 1: AI Tools, 2: Home, 3: Menu

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // Camera View (Left)
                CameraRecordingView(isActive: selectedTab == 0)
                    .ignoresSafeArea()
                    .tag(0)

                // AI Tools (Center-Left)
                AIToolsView()
                    .tag(1)

                // Main Content (Center-Right)
                ZStack {
                    // Gradient background
                    LinearGradient(
                        colors: [.gray.opacity(0.3), .gray.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack {
                        Image(systemName: "globe")
                            .imageScale(.large)
                            .foregroundStyle(.white)
                        Text("Hello, world!")
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                }
                .tag(2)

                // Menu View (Right)
                SideMenuView(isPresented: .constant(true))
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func signOut() {
        AppLogger.methodEntry(AppLogger.ui)
        authService.signOut()
        AppLogger.methodExit(AppLogger.ui)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService.preview)
}
