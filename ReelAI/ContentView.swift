//
//  ContentView.swift
//  ReelAI
//
//  Created by Kriss on 2/3/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var selectedTab = 1 // 0: Camera, 1: AI Tools, 2: Feed
    @State private var showSideMenu = false

    var body: some View {
        NavigationStack {
            ZStack {
                TabView(selection: $selectedTab) {
                    // Camera View (Left)
                    CameraRecordingView(isActive: selectedTab == 0)
                        .ignoresSafeArea()
                        .tag(0)

                    // AI Tools (Middle)
                    AIToolsView()
                        .tag(1)
                        
                    // Video Feed (Right)
                    VideoVerticalFeed()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selectedTab) { _, newValue in
                    Log.p(Log.app, Log.event, "User switched to tab: \(newValue)")
                    // Update video feed active state
                    VerticalVideoHandler.shared.setActive(newValue == 2)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            withAnimation {
                                showSideMenu.toggle()
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }

                // Side Menu Overlay
                if showSideMenu {
                    SideMenuView(isPresented: $showSideMenu)
                        .transition(.opacity)
                }
            }
            .spaceBackground()
        }
        .onAppear {
            Log.p(Log.app, Log.start, "Content view appeared")
            // Add notification observer for returning to AI Tools
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ReturnToAITools"),
                object: nil,
                queue: .main
            ) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = 1 // Switch to AI Tools tab
                }
            }
        }
        .onDisappear {
            Log.p(Log.app, Log.exit, "Content view disappeared")
            // Remove notification observer
            NotificationCenter.default.removeObserver(self)
        }
    }

    private func signOut() {
        Log.p(Log.auth, Log.start, "User initiated sign out")
        authService.signOut()
        Log.p(Log.auth, Log.exit, "Sign out completed")
    }

    private func testFirestoreWrite() {
        Log.p(Log.firebase, Log.start, "Starting Firestore write test")
        Log.p(Log.firebase, Log.event, "Checking auth state")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            Log.p(Log.firebase, Log.event, Log.error, "No authenticated user found")
            return
        }
        
        Log.p(Log.firebase, Log.event, "User authenticated: \(userId)")
        Log.p(Log.firebase, Log.save, "Creating test document")
        
        let testData: [String: Any] = [
            "testField": "Hello Firestore!",
            "timestamp": FieldValue.serverTimestamp(),
            "userId": userId
        ]
        
        Log.p(Log.firebase, Log.save, "Test data prepared")
        Log.p(Log.firebase, Log.save, "Attempting Firestore write")
        
        let db = Firestore.firestore()
        Log.p(Log.firebase, Log.event, "Using Firestore instance from GoogleService-Info.plist")
        Log.p(Log.firebase, Log.event, "Project ID: \(db.app.options.projectID ?? "unknown")")
        
        // Set with server timestamp to ensure server sync
        let docRef = db.collection("test_collection").document("test_document")
        docRef.setData(testData, merge: true) { error in
            if let error = error {
                Log.p(Log.firebase, Log.save, Log.error, "Firestore write failed: \(error.localizedDescription)")
                Log.p(Log.firebase, Log.save, Log.error, "Full error details: \(error)")
            } else {
                Log.p(Log.firebase, Log.save, Log.success, "Initial write successful")
                Log.p(Log.firebase, Log.event, "Waiting for server timestamp")
                
                // Wait for server timestamp to verify server sync
                docRef.getDocument(source: .server) { document, error in
                    if let error = error {
                        Log.p(Log.firebase, Log.read, Log.error, "Failed to verify server sync: \(error)")
                    } else if let timestamp = document?.data()?["timestamp"] as? Timestamp {
                        Log.p(Log.firebase, Log.read, Log.success, "Server sync confirmed")
                        Log.p(Log.firebase, Log.read, "Server timestamp: \(timestamp.dateValue())")
                    } else {
                        Log.p(Log.firebase, Log.read, Log.warning, "Write succeeded but no server timestamp found")
                    }
                }
            }
        }
    }
    
    private func testFirestoreRead() {
        Log.p(Log.firebase, Log.start, "Starting Firestore read test")
        Log.p(Log.firebase, Log.read, "Attempting to read test document")
        
        let db = Firestore.firestore()
        Log.p(Log.firebase, Log.event, "Using Firestore instance from GoogleService-Info.plist")
        
        db.collection("test_collection")
            .document("test_document")
            .getDocument { document, error in
                if let error = error {
                    Log.p(Log.firebase, Log.read, Log.error, "Firestore read failed: \(error.localizedDescription)")
                    Log.p(Log.firebase, Log.read, Log.error, "Full error details: \(error)")
                    return
                }
                
                guard let document = document else {
                    Log.p(Log.firebase, Log.read, Log.error, "No document found")
                    return
                }
                
                if document.exists {
                    Log.p(Log.firebase, Log.read, Log.success, "Document found")
                    if let data = document.data() {
                        Log.p(Log.firebase, Log.read, "Document data:")
                        data.forEach { key, value in
                            Log.p(Log.firebase, Log.read, "- \(key): \(value)")
                        }
                    }
                } else {
                    Log.p(Log.firebase, Log.read, Log.error, "Document does not exist")
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService.preview)
}
