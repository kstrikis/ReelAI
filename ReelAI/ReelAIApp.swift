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

        // Request permissions asynchronously
        Task {
            await requestPhotosPermissions()
        }

        Log.p(Log.app, Log.exit, "Application launch complete")
        return true
    }
    
    private func requestPhotosPermissions() async {
        Log.p(Log.app, Log.start, "Requesting Photos permissions")
        
        // Request addOnly permission first
        let addStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        Log.p(Log.app, Log.event, "Photos add permission result: \(addStatus.rawValue)")
        
        // Then request readWrite permission
        let readWriteStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        Log.p(Log.app, Log.event, "Photos readWrite permission result: \(readWriteStatus.rawValue)")
        
        // Log final permissions state
        Log.p(Log.app, Log.event, "Final Photos permissions - Add: \(addStatus.rawValue), ReadWrite: \(readWriteStatus.rawValue)")
    }
}

@main
struct ReelAIApp: App {
    // MARK: - Properties

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthenticationService()

    // Initialize URLCache on app start
    init() {
        setupURLCache()
    }
    
    // Configure URLCache for video caching
    private func setupURLCache() {
        // Calculate cache sizes based on device capacity
        // Use 10% of available disk space for video cache, up to 2GB
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: documentDirectory.path)
        let freeSpace = (systemAttributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        
        // Calculate disk cache size (10% of free space, max 2GB)
        let maxDiskSpace: Int64 = 2 * 1024 * 1024 * 1024 // 2GB in bytes
        let tenPercentFreeSpace = freeSpace / 10
        let diskCacheSize = min(tenPercentFreeSpace, maxDiskSpace)
        
        // Memory cache size (100MB or 5% of disk cache, whichever is smaller)
        let maxMemorySpace: Int = 100 * 1024 * 1024 // 100MB
        let fivePercentDiskCache = Int(diskCacheSize) / 20
        let memoryCacheSize = min(maxMemorySpace, fivePercentDiskCache)
        
        Log.p(Log.storage, Log.event, "Configuring URLCache with:")
        Log.p(Log.storage, Log.event, "- Memory cache: \(memoryCacheSize / 1024 / 1024)MB")
        Log.p(Log.storage, Log.event, "- Disk cache: \(diskCacheSize / 1024 / 1024)MB")
        
        let cache = URLCache(
            memoryCapacity: memoryCacheSize,
            diskCapacity: Int(diskCacheSize),
            diskPath: "com.reelai.cache.video"  // Namespaced cache path
        )
        URLCache.shared = cache
    }

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
