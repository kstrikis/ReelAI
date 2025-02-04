//
//  ContentView.swift
//  ReelAI
//
//  Created by Kriss on 2/3/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showMenu = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingProfile = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
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

                // Side menu
                if showMenu {
                    SideMenuView(isPresented: $showMenu)
                        .transition(.move(edge: .trailing))
                }
            }
            .navigationTitle("ReelAI")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { withAnimation { showMenu.toggle() } }) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.width < 0 {
                            dragOffset = gesture.translation.width
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.width < -50 {
                            withAnimation {
                                showMenu = true
                            }
                        }
                        dragOffset = 0
                    }
            )
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

