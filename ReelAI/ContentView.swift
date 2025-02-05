//
//  ContentView.swift
//  ReelAI
//
//  Created by Kriss on 2/3/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showingProfile = false
    @State private var selectedTab = 1 // 0: Camera, 1: Home, 2: Menu

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                // Camera View (Left)
                CameraRecordingView(isActive: selectedTab == 0)
                    .ignoresSafeArea()
                    .tag(0)

                // Main Content (Center)
                ZStack {
                    Color.black.ignoresSafeArea()
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
                .tag(1)

                // Menu View (Right)
                SideMenuView(isPresented: .constant(true))
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle("ReelAI")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingProfile = true }, label: {
                        Image(systemName: "person.circle")
                            .foregroundColor(.white)
                    })
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
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
