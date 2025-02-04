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
    @State private var showingProfile = false
    @State private var currentPage = 1  // 0: Camera, 1: Home, 2: Menu
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Camera View (Page 0)
                    CameraRecordingView()
                        .offset(x: -geometry.size.width + dragOffset)
                    
                    // Main Content (Page 1)
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
                    }
                    .offset(x: dragOffset)
                    
                    // Menu View (Page 2)
                    SideMenuView(isPresented: $showMenu)
                        .offset(x: geometry.size.width + dragOffset)
                }
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let translation = gesture.translation.width
                            let maxDrag = geometry.size.width / 2
                            
                            // Limit drag based on current page
                            switch currentPage {
                            case 0: // Camera page
                                dragOffset = min(maxDrag, max(0, translation))
                            case 1: // Home page
                                dragOffset = min(maxDrag, max(-maxDrag, translation))
                            case 2: // Menu page
                                dragOffset = min(0, max(-maxDrag, translation))
                            default:
                                break
                            }
                        }
                        .onEnded { gesture in
                            let velocity = gesture.predictedEndTranslation.width - gesture.translation.width
                            let translation = gesture.translation.width
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                // Determine page transition based on drag distance and velocity
                                if abs(translation) > geometry.size.width / 4 || abs(velocity) > 100 {
                                    if translation > 0 && currentPage > 0 {
                                        currentPage -= 1
                                        dragOffset = 0
                                    } else if translation < 0 && currentPage < 2 {
                                        currentPage += 1
                                        dragOffset = 0
                                    } else {
                                        dragOffset = 0
                                    }
                                } else {
                                    // Spring back to original position
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
            .navigationTitle("ReelAI")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingProfile = true }) {
                        Image(systemName: "person.circle")
                            .foregroundColor(.white)
                    }
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
