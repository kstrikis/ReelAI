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
                    
                    VStack(spacing: 20) {
                        Text("Firestore Test")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Button(action: testFirestoreWrite) {
                            Text("Test Write to Firestore")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                        Button(action: testFirestoreRead) {
                            Text("Test Read from Firestore")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(10)
                        }
                        
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

    private func testFirestoreWrite() {
        print("🧪 Starting Firestore write test...")
        print("🧪 Checking auth state...")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No authenticated user found!")
            return
        }
        
        print("✅ User authenticated: \(userId)")
        print("🧪 Creating test document...")
        
        let testData: [String: Any] = [
            "testField": "Hello Firestore!",
            "timestamp": FieldValue.serverTimestamp(),
            "userId": userId
        ]
        
        print("📝 Test data prepared: \(testData)")
        print("🔥 Attempting Firestore write...")
        
        let db = Firestore.firestore()
        print("🔥 Using Firestore instance from GoogleService-Info.plist")
        print("🔥 Project ID: \(db.app.options.projectID)")
        
        // Set with server timestamp to ensure server sync
        let docRef = db.collection("test_collection").document("test_document")
        docRef.setData(testData, merge: true) { error in
            if let error = error {
                print("❌ Firestore write failed!")
                print("❌ Error: \(error.localizedDescription)")
                print("❌ Full error details: \(error)")
            } else {
                print("✅ Initial write successful, waiting for server timestamp...")
                
                // Wait for server timestamp to verify server sync
                docRef.getDocument(source: .server) { document, error in
                    if let error = error {
                        print("❌ Failed to verify server sync: \(error)")
                    } else if let timestamp = document?.data()?["timestamp"] as? Timestamp {
                        print("✅ Server sync confirmed!")
                        print("✅ Server timestamp: \(timestamp.dateValue())")
                    } else {
                        print("⚠️ Write succeeded but no server timestamp found")
                    }
                }
            }
        }
    }
    
    private func testFirestoreRead() {
        print("🧪 Starting Firestore read test...")
        print("🔍 Attempting to read test document...")
        
        let db = Firestore.firestore()
        print("🔥 Using Firestore instance from GoogleService-Info.plist")
        
        db.collection("test_collection")
            .document("test_document")
            .getDocument { document, error in
                if let error = error {
                    print("❌ Firestore read failed!")
                    print("❌ Error: \(error.localizedDescription)")
                    print("❌ Full error details: \(error)")
                    return
                }
                
                guard let document = document else {
                    print("❌ No document found!")
                    return
                }
                
                if document.exists {
                    print("✅ Document found!")
                    print("📄 Document data:")
                    if let data = document.data() {
                        data.forEach { key, value in
                            print("  - \(key): \(value)")
                        }
                    }
                } else {
                    print("❌ Document does not exist!")
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService.preview)
}
