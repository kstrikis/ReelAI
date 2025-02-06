//
//  ReelAIApp.swift
//  ReelAI
//
//  Created by Kriss on 2/3/25.
//

import FirebaseAnalytics
import FirebaseAuth
import FirebaseCore
import FirebaseCrashlytics
import FirebaseStorage
import Photos
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Log.p(Log.app, Log.start, "Application launching")
        FirebaseApp.configure()

        // Block until we get both Photos permissions
        let semaphore = DispatchSemaphore(value: 0)

        // First request addOnly permission
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            Log.p(Log.app, Log.event, "Photos add permission result: \(status.rawValue)")

            // Then request readWrite permission
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Log.p(Log.app, Log.event, "Photos readWrite permission result: \(status.rawValue)")
                semaphore.signal()
            }
        }
        semaphore.wait()

        Log.p(Log.app, Log.exit, "Application launch complete")
        return true
    }
}

@main
struct ReelAIApp: App {
    // MARK: - Properties

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthenticationService()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                switch authService.authState {
                case .signedIn:
                    ContentView()
                        .environmentObject(authService)
                case .signedOut, .error:
                    LoginView()
                        .environmentObject(authService)
                }
            }
            .onAppear {
                Log.p(Log.app, Log.start, "ReelAI app root view appeared")
            }
            .onDisappear {
                Log.p(Log.app, Log.exit, "ReelAI app root view disappeared")
            }
        }
    }
}
