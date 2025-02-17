import SwiftUI
import AVKit
import FirebaseFirestore
// import FirebaseStorage // Not used
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
    @Published var isActive: Bool = false  // Track if this feed is currently visible
    private var isHandlingSwipe = false
    private var swipeHandlingTask: Task<Void, Never>?
    
    // Settings
    @Published private var settings = UserSettings.shared

    // Player management - simplified
    // var players: [String: AVPlayer] = [:] // Removed
    var playerItemObservations: [String: AnyCancellable] = [:] // Changed to AnyCancellable
    // var readyToPlayStates: [String: Bool] = [:] // Removed
    var cancellables = Set<AnyCancellable>() // Added to store cancellables
    
    // Actor for serializing player operations
    actor PlayerManager {
        var players: [String: AVPlayer] = [:]
        var readyToPlayStates: [String: Bool] = [:]
        
        func setPlayer(_ player: AVPlayer, for id: String) {
            players[id] = player
        }
        
        func getPlayer(for id: String) -> AVPlayer? {
            players[id]
        }
        
        func setReadyState(_ ready: Bool, for id: String) {
            readyToPlayStates[id] = ready
        }
        
        func isReady(id: String) -> Bool {
            readyToPlayStates[id] == true
        }
        
        func removePlayer(for id: String) {
            players.removeValue(forKey: id)
            readyToPlayStates.removeValue(forKey: id)
        }
        
        func updatePlaybackStates(isActive: Bool, currentId: String?) async {
            for (id, player) in players {
                let isReadyState = isReady(id: id)
                // Log.p(Log.video, Log.event, "Updating playback state for video: \(id), isActive: \(isActive), currentId: \(currentId ?? "nil"), isReady: \(isReadyState)")
                if !isActive || (currentId != nil && id != currentId) {
                    if await player.isPlaying {
                        player.pause()
                    }
                    player.volume = 0
                } else if id == currentId && isReadyState {
                    player.volume = 1
                    player.playImmediately(atRate: 1.0)
                }
            }
        }
        
        func getAllPlayers() -> [String: AVPlayer] {
            players
        }
    }
    
    let playerManager = PlayerManager()

    // Track video positions
    // private var videoPositions: [String: CMTime] = [:] // No longer used

    // Track active window size for video rendering
    private let activeWindowSize = 5 // Number of videos to keep active on each side of current
    private let preloadWindowSize = 3 // Number of videos to preload beyond active window
    
    // Track scroll progress for smooth audio transitions
    @Published private var scrollProgress: CGFloat = 0
    
    // Add URL cache
    var urlCache: [String: URL] = [:]
    
    // Constants for video loading
    private let batchSize = 6 // Number of videos to load at a time
    private let loadMoreThreshold = 3 // Load more when this many videos from the end
    
    private init() {
        isActive = false
        // loadVideos()
    }

    func loadVideos() {
        isLoading = true
        Task {
            do {
                Log.p(Log.video, Log.event, "Fetching \(batchSize) random videos...")
                let newVideos = try await FirestoreService.shared.fetchRandomVideos(count: batchSize)
                Log.p(Log.video, Log.event, "Appending \(newVideos.count) new videos to feed")
                videos.append(contentsOf: newVideos)
                
                // Pre-cache URLs for the newly loaded videos
                for video in newVideos {
                    if urlCache[video.id] == nil {
                        let url = try await FirestoreService.shared.getDownloadURL(for: video)
                        urlCache[video.id] = url
                    }
                }
                
                Log.p(Log.video, Log.event, "Received \(newVideos.count) videos")
                
                // If this is the initial load, set the first video as ready
                if !isFirstVideoReady && !videos.isEmpty {
                    isFirstVideoReady = true
                }
                
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Error loading videos: \(error)")
            }
            isLoading = false
        }
    }

    private func preparePlayer(for video: Video) async {
        // Don't prepare if we already have this player
        guard await playerManager.getPlayer(for: video.id) == nil else {
            Log.p(Log.video, Log.event, "Player already exists for video: \(video.id)")
            return
        }

        // Use atomic flag with timestamp to prevent duplicate preparation
        let preparationKey = "preparing_\(video.id)"
        let now = Date.now.timeIntervalSince1970
        let lastAttempt = UserDefaults.standard.double(forKey: preparationKey)
        if lastAttempt > 0 && (now - lastAttempt) < 3.0 {
            Log.p(Log.video, Log.event, "Recent preparation attempt for video: \(video.id), skipping")
            return
        }
        UserDefaults.standard.set(now, forKey: preparationKey)
        Log.p(Log.video, Log.event, "Preparing player for video: \(video.id)")
        
        do {
            // Create player and item BEFORE registering with manager
            let url: URL
            if let cachedURL = urlCache[video.id] {
                url = cachedURL
            } else {
                let fetchedURL = try await withTimeout(seconds: 2) { () async throws -> URL? in
                    try await FirestoreService.shared.getDownloadURL(for: video)
                }
                
                guard let downloadURL = fetchedURL else {
                    Log.p(Log.video, Log.event, Log.error, "Failed to get download URL or timed out")
                    UserDefaults.standard.removeObject(forKey: preparationKey)
                    return
                }
                
                url = downloadURL
                urlCache[video.id] = url
            }
            
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true,
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "Cache-Control": "public, max-age=3600"
                ]
            ])
            
            // Load essential properties with timeout
            try await withTimeout(seconds: 2) {
                async let tracks = asset.load(.tracks)
                async let duration = asset.load(.duration)
                _ = try await (tracks, duration)
            }
            
            // Create player and item
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            
            // Only NOW register the fully prepared player with the manager
            await playerManager.setPlayer(player, for: video.id)
            
            // Set up observations AFTER we know the player is valid
            setupPlayerObservations(player: player, playerItem: playerItem, videoId: video.id)
            
            Log.p(Log.video, Log.event, "Player initialized for video: \(video.id)")
            // Don't set ready state here - wait for the player item status
            
        } catch {
            Log.p(Log.video, Log.event, Log.error, "Failed to prepare player: \(error)")
            UserDefaults.standard.removeObject(forKey: preparationKey)
            // Make sure we don't have a partially prepared player
            await playerManager.removePlayer(for: video.id)
            playerItemObservations.removeValue(forKey: video.id)
        }
    }

    private func setupPlayerObservations(player: AVPlayer, playerItem: AVPlayerItem, videoId: String) {
        // Basic configuration for smooth playback
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = 0  // Start muted, will unmute when current

        // Set up looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player, weak self] _ in
            guard let player = player else { return }
            Task {
                await player.seek(to: .zero)
                // Only auto-play if we're active
                guard let self = self, self.isActive else { return }
                player.playImmediately(atRate: 1.0)
            }
        }

        // Observe player item status
        playerItem.publisher(for: \.status)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                Task { @MainActor in
                    switch status {
                    case .readyToPlay:
                        Log.p(Log.video, Log.event, "Player item ready to play: \(videoId)")
                        // Update ready state in PlayerManager
                        await self.playerManager.setReadyState(true, for: videoId)

                        // If this is the current video and it just became ready, ensure UI is updated
                        if videoId == self.videos[self.currentIndex].id {
                            Log.p(Log.video, Log.event, "🔄 Current video just became ready, updating UI")
                            // Force a UI refresh by toggling a state variable
                            self.objectWillChange.send()

                            // Only start playing if we're active
                            if self.isActive {
                                player.volume = 1
                                player.playImmediately(atRate: 1.0)
                            }
                        }
                    case .failed:
                        Log.p(Log.video, Log.event, Log.error, "Player item failed: \(String(describing: playerItem.error))")
                        // Clean up in PlayerManager
                        await self.playerManager.removePlayer(for: videoId)
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellables) // Store the observation in the cancellables set
    }

    // Helper for timeouts
    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(seconds: seconds)
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError(seconds: seconds)
            }
            
            group.cancelAll()
            return result
        }
    }

    private struct TimeoutError: Error {
        let seconds: Double
        var localizedDescription: String {
            "Operation timed out after \(seconds) seconds"
        }
    }

    // Remove the non-async version since it can't effectively handle async operations
    func getPlayerAsync(for video: Video, forceRecreate: Bool = false) async -> AVPlayer? {
        let maxRetries = 3
        var currentRetry = 0
        
        while currentRetry <= maxRetries {
            // Check actor's cache unless we're forcing recreation
            if !forceRecreate {
                if let player = await playerManager.getPlayer(for: video.id) {
                    // Verify the player is valid
                    if player.currentItem != nil {
                        Log.p(Log.video, Log.event, "Found valid player in actor cache for video: \(video.id)")
                        return player
                    } else {
                        Log.p(Log.video, Log.event, "Found invalid player in cache (no item), removing and recreating for video: \(video.id)")
                        await playerManager.removePlayer(for: video.id)
                        playerItemObservations.removeValue(forKey: video.id)
                    }
                }
            }

            Log.p(Log.video, Log.event, "No existing player found, preparing new player for video: \(video.id) (attempt \(currentRetry + 1)/\(maxRetries + 1))")
            // If no player exists or we're recreating, prepare one
            await preparePlayer(for: video)

            // Get the prepared player
            if let player = await playerManager.getPlayer(for: video.id) {
                // Verify the new player is valid
                if player.currentItem != nil {
                    return player
                } else {
                    Log.p(Log.video, Log.event, Log.error, "Newly created player has no item for video: \(video.id)")
                    await playerManager.removePlayer(for: video.id)
                    playerItemObservations.removeValue(forKey: video.id)
                }
            }
            
            if currentRetry < maxRetries {
                Log.p(Log.video, Log.event, Log.error, "Failed to get valid player for video: \(video.id), retrying...")
                // Exponential backoff: 0.5s, 1s, 2s
                let delay = Double(pow(2.0, Double(currentRetry))) * 0.25
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else {
                Log.p(Log.video, Log.event, Log.error, "Failed to get valid player after all retries for video: \(video.id)")
            }
            
            currentRetry += 1
        }
        
        return nil
    }

    func setActive(_ active: Bool) {
        isActive = active
        Task { @MainActor in
            let currentVideoId = videos.indices.contains(currentIndex) ? videos[currentIndex].id : nil
            await playerManager.updatePlaybackStates(isActive: active, currentId: currentVideoId)
        }
    }

    func updateScrollProgress(_ progress: CGFloat) {
        // Don't process scroll updates when inactive
        guard isActive else { return }
        
        scrollProgress = progress
        
        Task { @MainActor in
            // Get the relevant video indices based on scroll direction
            let currentVideoId = videos.indices.contains(currentIndex) ? videos[currentIndex].id : nil
            let nextVideoId = progress > 0 && videos.indices.contains(currentIndex + 1) ? videos[currentIndex + 1].id : nil
            let prevVideoId = progress < 0 && videos.indices.contains(currentIndex - 1) ? videos[currentIndex - 1].id : nil
            
            // Update playback states and volumes
            for (videoId, player) in await playerManager.getAllPlayers() {
                let isReady = await playerManager.isReady(id: videoId)
                
                if videoId == currentVideoId {
                    // Current video
                    player.volume = Float(1 - abs(progress))
                    if !player.isPlaying && isReady {
                        player.playImmediately(atRate: 1.0)
                    }
                } else if videoId == nextVideoId && progress > 0 {
                    // Next video during downward scroll
                    player.volume = Float(progress)
                    if !player.isPlaying && isReady {
                        player.playImmediately(atRate: 1.0)
                    }
                } else if videoId == prevVideoId && progress < 0 {
                    // Previous video during upward scroll
                    player.volume = Float(-progress)
                    if !player.isPlaying && isReady {
                        player.playImmediately(atRate: 1.0)
                    }
                } else {
                    // Any other video should be paused
                    if player.isPlaying {
                        player.pause()
                        await player.seek(to: .zero)
                    }
                    player.volume = 0
                }
            }
        }
    }

    func handleIndexChange(_ newIndex: Int) {
        // Added debug log to confirm count here, too
        Log.p(Log.video, Log.event, "handleIndexChange() called with newIndex \(newIndex), videos.count = \(videos.count)")

        // Don't process index changes when inactive
        guard isActive else {
            Log.p(Log.video, Log.event, "Ignoring index change to \(newIndex) because feed is inactive")
            return
        }

        guard newIndex >= 0 && newIndex < videos.count else {
            Log.p(Log.video, Log.event, Log.error, "Invalid index change requested: \(newIndex), videos count: \(videos.count)")
            return
        }

        Log.p(Log.video, Log.event, "🔄 Transitioning from index \(currentIndex) to \(newIndex)")
        currentIndex = newIndex

        // Check if we need to load more videos
        if newIndex >= videos.count - loadMoreThreshold {
            Log.p(Log.video, Log.event, "Reached load threshold at index \(newIndex), loading more videos")
            loadVideos()
        }

        Task { @MainActor in
            // PRIORITY 1: Get the current video playing immediately
            let currentVideo = videos[newIndex]
            let currentVideoId = currentVideo.id
            
            // If we don't have a player for the current video, prepare it immediately
            if await playerManager.getPlayer(for: currentVideoId) == nil {
                await preparePlayer(for: currentVideo)
            }
            
            // Update playback state for just the current video
            await playerManager.updatePlaybackStates(isActive: true, currentId: currentVideoId)
            
            // PRIORITY 2: Asynchronously prepare nearby videos
            Task { @MainActor in
                let preloadStart = max(0, newIndex - (activeWindowSize + preloadWindowSize))
                let preloadEnd = min(videos.count - 1, newIndex + (activeWindowSize + preloadWindowSize))
                
                // Create a sorted array of indices prioritizing closest to current
                let sortedIndices = (preloadStart...preloadEnd).sorted {
                    abs($0 - newIndex) < abs($1 - newIndex)
                }
                
                // Skip the current index since we already handled it
                for i in sortedIndices where i != newIndex {
                    let video = videos[i]
                    if await playerManager.getPlayer(for: video.id) == nil {
                        await preparePlayer(for: video)
                    }
                }
                
                // Only after all preparation is done, do final cleanup
                await cleanupDistantPlayers()
                
                // Log final state
                Log.p(Log.video, Log.event, "🎯 Player states in preload window:")
                for i in preloadStart...preloadEnd {
                    let video = videos[i]
                    let playerExists = await playerManager.getPlayer(for: video.id) != nil
                    let playerReady = await playerManager.isReady(id: video.id)
                    Log.p(Log.video, Log.event, "  [\(i)]: \(video.id) - exists=\(playerExists), ready=\(playerReady)")
                }
            }
        }
    }
    
    private func cleanupDistantPlayers() async {
        let currentCleanUpWindowSize = activeWindowSize + preloadWindowSize
        let minIndex = max(0, currentIndex - currentCleanUpWindowSize)
        let maxIndex = min(videos.count - 1, currentIndex + currentCleanUpWindowSize)
        
        // Get all players that should exist based on index positions
        var validPlayersByIndex: [Int: (videoId: String, player: AVPlayer)] = [:]
        for (index, video) in videos.enumerated() {
            if index >= minIndex && index <= maxIndex {
                if let player = await playerManager.getPlayer(for: video.id) {
                    validPlayersByIndex[index] = (video.id, player)
                }
            }
        }
        
        // Clean up any players for indices outside our window
        for (videoId, player) in await playerManager.getAllPlayers() {
            var shouldKeepPlayer = false
            
            // Check if this player is needed for any valid index position
            for index in minIndex...maxIndex {
                if index < videos.count && videos[index].id == videoId {
                    shouldKeepPlayer = true
                    break
                }
            }
            
            if !shouldKeepPlayer {
                Log.p(Log.video, Log.event, "Cleaning up player for video \(videoId) as it's not needed at any index in window \(minIndex)...\(maxIndex)")
                await playerManager.removePlayer(for: videoId)
                playerItemObservations.removeValue(forKey: videoId)
                
                if player.isPlaying { // Await the isPlaying property
                    player.pause()
                }
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    // func updateVideoPosition(for videoId: String, position: CMTime) { // No longer used
    //     videoPositions[videoId] = position
    // }

    func isActiveIndex(_ index: Int) -> Bool {
        let activeRange = max(0, currentIndex - activeWindowSize)...min(videos.count - 1, currentIndex + activeWindowSize)
        Log.p(Log.video, Log.event, "Checking if index \(index) is active. Current index: \(currentIndex), Active range: \(activeRange)")
        return activeRange.contains(index)
    }
}

struct VideoVerticalFeed: View {
    @StateObject private var handler = VerticalVideoHandler.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var dragOffset = CGSize.zero
    @State private var dragDirection: DragDirection = .none
    @State private var scrollPositionThreshold = 1 // Minimum index change required to trigger update
    @Environment(\.dismiss) private var dismiss
    
    private enum DragDirection {
        case horizontal, vertical, none
    }
    
    var body: some View {
        let fullScreenSize = UIScreen.main.bounds.size
        
        GeometryReader { geometry in
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
                                    index: index,
                                    size: fullScreenSize
                                )
                                .id(index)
                                .frame(width: fullScreenSize.width, height: fullScreenSize.height)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: .init(
                        get: {
                            handler.currentIndex
                        },
                        set: { newIndex in
                            guard let newIndex = newIndex,
                                  newIndex >= 0 && newIndex < handler.videos.count else {
                                return
                            }
                            handler.handleIndexChange(newIndex)
                        }
                    ))
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                let progress = value.translation.height / fullScreenSize.height
                                handler.updateScrollProgress(-progress) // Invert because scroll up means next video
                            }
                            .onEnded { _ in
                                handler.updateScrollProgress(0)
                            }
                    )
                    .scrollDisabled(dragDirection == .horizontal)
                }
            }
        }
        .frame(width: fullScreenSize.width, height: fullScreenSize.height)
        .ignoresSafeArea()
        .onAppear {
            Log.p(Log.video, Log.start, "Vertical video feed appeared")
            handler.setActive(true)
            // Call handleIndexChange to ensure initial preloading
            Task {
                handler.loadVideos() // Await the initial load
                handler.handleIndexChange(handler.currentIndex)
            }
        }
        .onDisappear {
            Log.p(Log.video, Log.exit, "Vertical video feed disappeared")
            handler.setActive(false)
        }
        // Add scene phase handling
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                handler.setActive(false)
            case .active:
                // Only activate if we're actually visible
                // This prevents activation during TabView preloading
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                   let rootViewController = window.rootViewController,
                   rootViewController.view.subviews.contains(where: { $0.bounds.intersects(window.bounds) }) {
                    handler.setActive(true)
                }
            @unknown default:
                break
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
                handler.loadVideos()
            }
            .foregroundColor(.blue)
        }
    }
}

// Add VideoOverlay view model
@MainActor
public class VideoOverlayViewModel: ObservableObject {
    @Published public var isLiked: Bool = false
    @Published public var isDisliked: Bool = false
    @Published private(set) var currentLikeCount: Int
    @Published private(set) var currentDislikeCount: Int
    private var cancellables = Set<AnyCancellable>()
    
    public init(video: Video) {
        self.currentLikeCount = video.engagement.likeCount
        self.currentDislikeCount = video.engagement.dislikeCount
    }
    
    public func handleLike(for video: Video) {
        if isLiked {
            // Unlike
            isLiked = false
            currentLikeCount -= 1
            FirestoreService.shared.updateVideoLike(videoId: video.id, isLike: true, increment: false)
                .sink(receiveCompletion: { _ in }, receiveValue: { })
                .store(in: &cancellables)
        } else {
            // Like
            isLiked = true
            currentLikeCount += 1
            if isDisliked {
                isDisliked = false
                currentDislikeCount -= 1
                // Remove dislike first
                FirestoreService.shared.updateVideoLike(videoId: video.id, isLike: false, increment: false)
                    .sink(receiveCompletion: { _ in }, receiveValue: { })
                    .store(in: &cancellables)
            }
            FirestoreService.shared.updateVideoLike(videoId: video.id, isLike: true, increment: true)
                .sink(receiveCompletion: { _ in }, receiveValue: { })
                .store(in: &cancellables)
        }
    }
    
    public func handleDislike(for video: Video) {
        if isDisliked {
            // Remove dislike
            isDisliked = false
            currentDislikeCount -= 1
            FirestoreService.shared.updateVideoLike(videoId: video.id, isLike: false, increment: false)
                .sink(receiveCompletion: { _ in }, receiveValue: { })
                .store(in: &cancellables)
        } else {
            // Dislike
            isDisliked = true
            currentDislikeCount += 1
            if isLiked {
                isLiked = false
                currentLikeCount -= 1
                // Remove like first
                FirestoreService.shared.updateVideoLike(videoId: video.id, isLike: true, increment: false)
                    .sink(receiveCompletion: { _ in }, receiveValue: { })
                    .store(in: &cancellables)
            }
            FirestoreService.shared.updateVideoLike(videoId: video.id, isLike: false, increment: true)
                .sink(receiveCompletion: { _ in }, receiveValue: { })
                .store(in: &cancellables)
        }
    }
}

public struct VideoOverlay: View {
    private let video: Video
    private let player: AVPlayer
    @Binding private var isVisible: Bool
    @State private var hideTask: Task<Void, Never>?
    @State private var isPlaying: Bool = true
    @StateObject private var viewModel: VideoOverlayViewModel
    
    public init(video: Video, player: AVPlayer, isVisible: Binding<Bool>) {
        self.video = video
        self.player = player
        self._isVisible = isVisible
        self._viewModel = StateObject(wrappedValue: VideoOverlayViewModel(video: video))
    }
    
    public var body: some View {
        VStack {
            // Add extra top padding
            Color.clear.frame(height: 50)
            
            // Video info moved to top
            VStack(alignment: .leading, spacing: 8) {
                Text(video.title)
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)
                
                if let description = video.description {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                }
                
                HStack {
                    Text(video.username)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    // Engagement stats
                    HStack(spacing: 16) {
                        Label("\(video.engagement.viewCount)", systemImage: "eye.fill")
                        Label("\(viewModel.currentLikeCount)", systemImage: "hand.thumbsup.fill")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.7), .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Spacer()
        }
        .overlay(alignment: .center) {
            // Play/Pause button
            Button(action: {
                if isPlaying {
                    player.pause()
                } else {
                    player.play()
                }
                isPlaying.toggle()
                scheduleOverlayHide()
            }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .overlay(alignment: .trailing) {
            // Like/Dislike buttons
            VStack(spacing: 16) {
                Button(action: {
                    viewModel.handleLike(for: video)
                    scheduleOverlayHide()
                }) {
                    VStack {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.system(size: 30))
                            .foregroundColor(viewModel.isLiked ? .blue : .white.opacity(0.8))
                        Text("\(viewModel.currentLikeCount)")
                            .font(.caption)
                    }
                }
                
                Button(action: {
                    viewModel.handleDislike(for: video)
                    scheduleOverlayHide()
                }) {
                    VStack {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.system(size: 30))
                            .foregroundColor(viewModel.isDisliked ? .red : .white.opacity(0.8))
                        Text("\(viewModel.currentDislikeCount)")
                            .font(.caption)
                    }
                }
            }
            .padding(.trailing, 20)
            .padding(.top, 100)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .onAppear {
            // Initialize isPlaying based on player's current state AND set it to true since we auto-play on appear
            isPlaying = true
            
            // Observe player's time control status changes
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemTimeJumped,
                object: player.currentItem,
                queue: .main
            ) { _ in
                isPlaying = player.rate != 0 || player.timeControlStatus == .playing
            }
            
            // Also observe rate changes
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: player.currentItem,
                queue: .main
            ) { _ in
                isPlaying = player.rate != 0 || player.timeControlStatus == .playing
            }
            
            // Add observation for when playback actually starts
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemNewAccessLogEntry,
                object: player.currentItem,
                queue: .main
            ) { _ in
                isPlaying = player.rate != 0 || player.timeControlStatus == .playing
            }
            
            scheduleOverlayHide()
        }
    }
    
    private func scheduleOverlayHide() {
        // Cancel any existing hide task
        hideTask?.cancel()
        
        // Create a new hide task
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    isVisible = false
                }
            }
        }
    }
}

// Update VideoVerticalPlayer
struct VideoVerticalPlayer: View {
    let video: Video
    let index: Int
    @StateObject private var playerWrapper = PlayerWrapper()
    let size: CGSize
    @StateObject private var handler = VerticalVideoHandler.shared
    @State private var isOverlayVisible = false

    // Helper class to wrap the AVPlayer and make it Observable
    class PlayerWrapper: ObservableObject {
        var player: AVPlayer?

        func setPlayer(_ player: AVPlayer) {
            if self.player == nil {
                self.player = player
            }
        }
    }

    var body: some View {
        ZStack {
            if let player = playerWrapper.player {
                VerticalFeedVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .onAppear {
                        if player.currentItem == nil {
                            Log.p(Log.video, Log.event, Log.error, "⚫️ BLACK SCREEN DETECTED: Player exists but has no currentItem for video: [\(index)] \(video.id), recreating player...")
                            // Reset the player wrapper to force recreation
                            playerWrapper.player = nil
                            // Trigger player recreation
                            Task {
                                if let newPlayer = await handler.getPlayerAsync(for: video, forceRecreate: true) {
                                    playerWrapper.setPlayer(newPlayer)
                                }
                            }
                        } else if player.status != .readyToPlay {
                            Log.p(Log.video, Log.event, Log.error, "⚫️ BLACK SCREEN DETECTED: Player exists, item exists, but status is not readyToPlay for video: [\(index)] \(video.id), status: \(player.status)")
                        } else {
                            Log.p(Log.video, Log.event, "🟢 Player is ready on appearance for video: [\(index)] \(video.id)")
                        }
                    }
                    .overlay {
                        if let player = playerWrapper.player {
                            VideoOverlay(
                                video: video,
                                player: player,
                                isVisible: $isOverlayVisible
                            )
                        }
                    }
                    .onTapGesture {
                        isOverlayVisible.toggle()
                    }
            } else {
                // Placeholder while video loads
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    
                    // Index and Video ID text
                    Text("[\(index)] \(video.id)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                }
                .onAppear {
                    Log.p(Log.video, Log.event, Log.error, "⚫️ BLACK SCREEN DETECTED: Player is nil for video: [\(index)] \(video.id)")
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped() // Ensure content doesn't overflow
        .background(Color.black)
        .task {
            // Load player asynchronously and assign to the wrapper
            if playerWrapper.player == nil {
                if let player = await handler.getPlayerAsync(for: video) {
                    playerWrapper.setPlayer(player) // Use setPlayer to ensure only one assignment
                }
            }
        }
    }
}

struct VerticalFeedVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        
        // Prevent the controller from trying to access transform properties
        if let playerLayer = controller.view.layer as? AVPlayerLayer {
            playerLayer.videoGravity = .resizeAspectFill
        }
        
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No updates needed
    }
}

// Add isPlaying extension for AVPlayer
private extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
} 