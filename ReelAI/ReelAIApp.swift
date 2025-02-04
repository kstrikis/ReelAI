//
//  ReelAIApp.swift
//  ReelAI
//
//  Created by Kriss on 2/3/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseAnalytics
import FirebaseCrashlytics

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.methodEntry(AppLogger.auth)
        FirebaseApp.configure()
        AppLogger.methodExit(AppLogger.auth)
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
                AppLogger.methodEntry(AppLogger.ui, "ReelAIApp.body")
            }
        }
    }
}

