import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage
import Combine

// MARK: - Vertical Video Feed System

@MainActor
class VerticalVideoHandler: ObservableObject {
    // Shared instance
    static let shared = VerticalVideoHandler()

    // Core data
    @Published var videos: [Video] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var isFirstVideoReady = false
    @Published private(set) var activeVideoIds: Set<String> = []
    private var isHandlingSwipe = false
    private var swipeHandlingTask: Task<Void, Never>?

    // Player management
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var preloadTasks: [String: Task<Void, Error>] = [:]
    private var playerSubjects: [String: CurrentValueSubject<AVPlayer?, Never>] = [:]
    var cancellables: Set<AnyCancellable> = []
    private var initialBatchSize = 8
    private var paginationBatchSize = 5

    // Track video positions
    private var videoPositions: [String: CMTime] = [:]

    private init() {
        loadInitialVideos()
    }

    func loadInitialVideos() {
        Log.p(Log.video, Log.event, "Loading initial batch of random videos")

        isLoading = true
        Task {
            do {
                // Use the existing FirestoreService
                let initialCheck = try await FirestoreService.shared.fetchVideoBatch(startingAfter: nil, limit: 1)
                if initialCheck.isEmpty {
                    Log.p(Log.video, Log.event, "No videos found, attempting to seed...")
                    try await FirestoreService.shared.seedVideos()
                }

                // Use the new random videos function
                let batch = try await FirestoreService.shared.fetchRandomVideos(count: initialBatchSize)
                Log.p(Log.video, Log.event, "Received \(batch.count) random videos")

                await MainActor.run {
                    self.videos = batch
                    self.isLoading = false
                    self.isFirstVideoReady = !batch.isEmpty
                    self.preloadInitialVideos()
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Initial load failed: \(error)")
                await MainActor.run { isLoading = false }
            }
        }
    }

    func loadMoreVideos() {
        // Prevent loading during swipe animations or if already loading
        guard !isLoading && !isHandlingSwipe else { 
            Log.p(Log.video, Log.event, "Skipping loadMoreVideos - System is \(isHandlingSwipe ? "handling swipe" : "already loading")")
            return 
        }
        isLoading = true

        Task {
            do {
                // Use random videos for pagination too
                let newVideos = try await FirestoreService.shared.fetchRandomVideos(count: paginationBatchSize)
                Log.p(Log.video, Log.event, "Fetched \(newVideos.count) more random videos")
                
                // Double check we're not in the middle of a swipe before applying changes
                guard !isHandlingSwipe else {
                    Log.p(Log.video, Log.event, "Discarding fetched videos - system is handling swipe")
                    isLoading = false
                    return
                }
                
                await MainActor.run {
                    // Append the newly fetched videos to the existing array.
                    self.videos.append(contentsOf: newVideos)
                    // Preload videos after appending them, but *avoid* autoplaying them.
                    for video in newVideos {
                        preloadVideo(video)
                    }
                    self.isLoading = false
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Failed to fetch more videos: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Player Management

    func getPlayer(for video: Video) -> AVPlayer? {
        return preloadedPlayers[video.id]
    }

    func playerPublisher(for videoId: String) -> AnyPublisher<AVPlayer?, Never> {
        if playerSubjects[videoId] == nil {
            playerSubjects[videoId] = CurrentValueSubject<AVPlayer?, Never>(preloadedPlayers[videoId])
        }
        return playerSubjects[videoId]!.eraseToAnyPublisher()
    }

    private func preloadInitialVideos() {
        guard !videos.isEmpty else { return }

        // Preload the first four videos instead of just two
        let initialVideos = Array(videos.prefix(4))
        for video in initialVideos {
            preloadVideo(video)
        }
    }

    private func preloadVideo(_ video: Video) {
        let id = video.id
        if preloadedPlayers[id] != nil { return }

        Task {
            do {
                Log.p(Log.video, Log.event, "Preloading video: \(id)")
                guard let url = try await FirestoreService.shared.getVideoDownloadURL(videoId: id) else {
                    Log.p(Log.video, Log.event, Log.error, "Failed to get download URL for \(id)")
                    return
                }

                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: playerItem)
                
                // Configure for smooth playback
                player.automaticallyWaitsToMinimizeStalling = false

                await MainActor.run {
                    preloadedPlayers[id] = player
                    playerSubjects[id]?.send(player)
                    Log.p(Log.video, Log.event, "Successfully preloaded video: \(id)")

                    // Auto-play if this is the current video
                    if videos.indices.contains(currentIndex), videos[currentIndex].id == id {
                        player.play()
                    }
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Preload failed for \(id): \(error)")
            }
        }
    }

    func handleIndexChange(_ newIndex: Int) {
        Log.p(Log.video, Log.event, "Beginning index change handling - New Index: \(newIndex)")
        
        // Cancel any existing swipe handling task
        swipeHandlingTask?.cancel()
        isHandlingSwipe = true
        
        // Create new task for this swipe
        swipeHandlingTask = Task {
            defer { 
                // Ensure we reset the flag when the task completes or is cancelled
                isHandlingSwipe = false 
            }
            
            // Validate index bounds
            guard newIndex >= 0 && newIndex < videos.count else {
                Log.p(Log.video, Log.event, Log.error, "Invalid index: \(newIndex), videos count: \(videos.count)")
                return
            }

            // 1. Save position and pause previous video
            if videos.indices.contains(currentIndex), let oldPlayer = preloadedPlayers[videos[currentIndex].id] {
                videoPositions[videos[currentIndex].id] = oldPlayer.currentTime()
                oldPlayer.pause() // Targeted pause of the previous video
                Log.p(Log.video, Log.event, "Pausing and saving position for video: \(videos[currentIndex].id) at position: \(oldPlayer.currentTime().seconds)")
            }

            // 2. Update current index
            currentIndex = newIndex
            Log.p(Log.video, Log.event, "Updated current index to: \(newIndex)")

            // 3. Handle current video - PRIORITY
            let currentVideo = videos[newIndex]
            if let player = preloadedPlayers[currentVideo.id] {
                // Restore previous position or start from beginning
                let position = videoPositions[currentVideo.id] ?? .zero
                
                // Ensure we're on the main thread for playback
                Task { @MainActor in
                    player.seek(to: position)
                    player.play()
                    Log.p(Log.video, Log.event, "Playing existing player for current video: \(currentVideo.id) from position: \(position.seconds)")
                }
            } else {
                Log.p(Log.video, Log.event, "Preloading current video: \(currentVideo.id)")
                preloadVideo(currentVideo)
            }

            // 4. Start a background task for non-critical operations
            Task {
                // Wait for swipe animation to complete (typical iOS animation duration is 0.3s)
                // Adding a bit more time (0.5s total) to ensure complete smoothness
                try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms delay
                
                // Check for pagination first since it's most important for UX
                if newIndex >= videos.count - 4 {
                    Log.p(Log.video, Log.event, "Near end of list, triggering pagination")
                    await MainActor.run {
                        loadMoreVideos()
                    }
                }

                // Calculate which videos need preloading (excluding current and already loaded)
                var adjacentIndices = Set<Int>()
                // Add indices before current
                for offset in 1...3 {
                    adjacentIndices.insert(max(0, newIndex - offset))
                }
                // Add current index
                adjacentIndices.insert(newIndex)
                // Add indices after current
                for offset in 1...3 {
                    adjacentIndices.insert(min(videos.count - 1, newIndex + offset))
                }
                
                let preloadIndices = adjacentIndices.filter { index in
                    let video = videos[index]
                    return preloadedPlayers[video.id] == nil // Only preload if not already loaded
                }
                
                if !preloadIndices.isEmpty {
                    Log.p(Log.video, Log.event, "Preloading adjacent indices: \(preloadIndices)")
                    
                    // Preload one at a time to avoid overwhelming the system
                    for index in preloadIndices {
                        let video = videos[index]
                        await MainActor.run {
                            preloadVideo(video)
                        }
                        // Small delay between each preload to maintain smoothness
                        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms delay
                    }
                }

                // Finally, cleanup inactive players
                await MainActor.run {
                    cleanupInactivePlayers(around: newIndex)
                }
            }
        }
    }

    private func cleanupInactivePlayers(around index: Int) {
        // ALWAYS keep the current video's player
        var keepIds = Set([videos[index].id])
        
        // Add adjacent videos we want to keep (increased window further)
        var keepIndices = Set<Int>()
        // Add indices before current
        for offset in 1...3 {
            keepIndices.insert(max(0, index - offset))
        }
        // Add current index
        keepIndices.insert(index)
        // Add indices after current
        for offset in 1...3 {
            keepIndices.insert(min(videos.count - 1, index + offset))
        }
        
        keepIds.formUnion(keepIndices.compactMap { videos.indices.contains($0) ? videos[$0].id : nil })
        Log.p(Log.video, Log.event, "Keeping video IDs: \(keepIds)")

        // Remove players and positions not in keepIds
        for id in preloadedPlayers.keys where !keepIds.contains(id) {
            Log.p(Log.video, Log.event, "Cleaning up player for video: \(id)")
            if let player = preloadedPlayers[id] {
                player.pause()  // Ensure playback is stopped
                player.replaceCurrentItem(with: nil)  // Remove the item to free up resources
                Log.p(Log.video, Log.event, "Stopped playback and cleared item for video: \(id)")
            }
            preloadedPlayers[id] = nil
            playerSubjects[id]?.send(nil)
            playerSubjects[id] = nil
            videoPositions.removeValue(forKey: id)  // Clean up positions too
            Log.p(Log.video, Log.event, "Removed all references for video: \(id)")
        }
    }

    func updateActiveVideos(_ videoId: String) {
        activeVideoIds.insert(videoId)
    }

    func updateVideoPosition(for videoId: String, position: CMTime) {
        videoPositions[videoId] = position
    }
}

struct VideoVerticalFeed: View {
    @StateObject private var handler = VerticalVideoHandler.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var dragOffset = CGSize.zero
    @State private var dragDirection: DragDirection = .none
    @Environment(\.dismiss) private var dismiss
    
    private enum DragDirection {
        case horizontal, vertical, none
    }
    
    var body: some View {
        let fullScreenSize = UIScreen.main.bounds.size
        
        GeometryReader { _ in  // We'll use fullScreenSize instead of geometry
            ZStack {
                Color.black.ignoresSafeArea()

                if handler.videos.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(handler.videos.indices, id: \.self) { index in
                                VideoVerticalPlayer(
                                    video: handler.videos[index],
                                    player: handler.getPlayer(for: handler.videos[index]),
                                    size: fullScreenSize
                                )
                                .id(handler.videos[index].id)
                                .frame(width: fullScreenSize.width, height: fullScreenSize.height)
                                .border(Color.blue.opacity(0.5), width: 2)  // Debug border
                            }
                        }
                        .border(Color.red.opacity(0.5), width: 2)  // Debug border for LazyVStack
                    }
                    .scrollTargetLayout()
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: .init(get: {
                        handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex].id : nil
                    }, set: { newPosition in
                        if let newPosition,
                           let index = handler.videos.firstIndex(where: { $0.id == newPosition }),
                           index != handler.currentIndex {  // Only trigger if index actually changed
                            handler.handleIndexChange(index)
                        }
                    }))
                    .ignoresSafeArea()
                    .scrollDisabled(dragDirection == .horizontal)
                }
            }
        }
        .frame(width: fullScreenSize.width, height: fullScreenSize.height)  // Force full screen size
        .ignoresSafeArea()
        .onAppear {
            Log.p(Log.video, Log.start, "Vertical video feed appeared")
            if let currentVideo = handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex] : nil,
               let player = handler.getPlayer(for: currentVideo) {
                player.play()
            }
        }
        .onDisappear {
            Log.p(Log.video, Log.exit, "Vertical video feed disappeared")
            if let currentVideo = handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex] : nil,
               let player = handler.getPlayer(for: currentVideo) {
                player.pause()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)
            Text("No videos available")
                .foregroundColor(.white)
            Button("Retry") {
                handler.loadInitialVideos()
            }
            .foregroundColor(.blue)
        }
    }
}

struct VideoVerticalPlayer: View {
    let video: Video
    let player: AVPlayer?
    let size: CGSize
    
    var body: some View {
        ZStack {
            if let player = player {
                CustomVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            } else {
                // Placeholder while video loads
                Rectangle()
                    .fill(Color.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
            
            // Overlay controls and UI elements
            VStack {
                // Top controls (if any)
                Spacer()
                // Bottom controls (if any)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(0)
        }
        .frame(width: size.width, height: size.height)
        .clipped() // Ensure content doesn't overflow
        .background(Color.black)
    }
} 