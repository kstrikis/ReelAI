import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage
import Combine

// MARK: - Consolidated Video Feed System

@MainActor
class UnifiedVideoHandler: ObservableObject {
    // Shared instance
    static let shared = UnifiedVideoHandler()

    // Core data
    @Published var videos: [Video] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var isFirstVideoReady = false //Kept for any potential empty state management
    @Published private(set) var activeVideoIds: Set<String> = [] //Probably unused at the moment, but no harm done

    // Player management
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var preloadTasks: [String: Task<Void, Error>] = [:]
    private var playerSubjects: [String: CurrentValueSubject<AVPlayer?, Never>] = [:] // Keep for future use for observing player properties.
    var cancellables: Set<AnyCancellable> = []  // For managing Combine subscriptions
    private var initialBatchSize = 5 // How many to get first
    private var paginationBatchSize = 3 // How many more to add on

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

    //Function to load more videos.
    func loadMoreVideos() {
           // Prevent multiple simultaneous loads
           guard !isLoading else { return }
           isLoading = true

           Task {
               do {
                   // Use random videos for pagination too
                   let newVideos = try await FirestoreService.shared.fetchRandomVideos(count: paginationBatchSize)
                   Log.p(Log.video, Log.event, "Fetched \(newVideos.count) more random videos")
                   await MainActor.run{
                       // Append the newly fetched videos to the existing array.
                       self.videos.append(contentsOf: newVideos)
                       // Preload videos after appending them, but *avoid* autoplaying them.
                       for video in newVideos {
                            preloadVideo(video) //Ensure new videos are preloaded as they are added.
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
        //  'id' is guaranteed by @DocumentID after loading from Firestore
        return preloadedPlayers[video.id]
    }

    // Keep this function -- it is correct and useful for the future
    func playerPublisher(for videoId: String) -> AnyPublisher<AVPlayer?, Never> {
        if playerSubjects[videoId] == nil {
            playerSubjects[videoId] = CurrentValueSubject<AVPlayer?, Never>(preloadedPlayers[videoId])
        }
        return playerSubjects[videoId]!.eraseToAnyPublisher()
    }

    private func preloadInitialVideos() {
        guard !videos.isEmpty else { return }

        // Preload the first two videos.
        let initialVideos = Array(videos.prefix(2))
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
        
        // Validate index bounds
        guard newIndex >= 0 && newIndex < videos.count else {
            Log.p(Log.video, Log.event, Log.error, "Invalid index: \(newIndex), videos count: \(videos.count)")
            return
        }

        // 1. Save position and pause previous video
        if videos.indices.contains(currentIndex), let oldPlayer = preloadedPlayers[videos[currentIndex].id] {
            videoPositions[videos[currentIndex].id] = oldPlayer.currentTime()
            // oldPlayer.pause()  // DISABLED PAUSE POINT #1
            Log.p(Log.video, Log.event, "Saving position for video: \(videos[currentIndex].id) at position: \(oldPlayer.currentTime().seconds)")
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
            // Add a 1-second delay before starting background operations
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Check for pagination first since it's most important for UX
            if newIndex >= videos.count - 4 {
                Log.p(Log.video, Log.event, "Near end of list, triggering pagination")
                await MainActor.run {
                    loadMoreVideos()
                }
            }

            // Calculate which videos need preloading (excluding current and already loaded)
            let adjacentIndices = Set([
                max(0, newIndex - 1),
                min(videos.count - 1, newIndex + 1)
            ])
            
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
                    // Add a small delay between each preload
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            // Finally, cleanup inactive players
            await MainActor.run {
                cleanupInactivePlayers(around: newIndex)
            }
        }
    }

    private func cleanupInactivePlayers(around index: Int) {
        // ALWAYS keep the current video's player
        var keepIds = Set([videos[index].id])
        
        // Add adjacent videos we want to keep
        let keepIndices = Set([
            max(0, index - 1),
            index,
            min(videos.count - 1, index + 1)
        ])
        
        keepIds.formUnion(keepIndices.compactMap { videos.indices.contains($0) ? videos[$0].id : nil })
        Log.p(Log.video, Log.event, "Keeping video IDs: \(keepIds)")

        // Remove players and positions not in keepIds
        for id in preloadedPlayers.keys where !keepIds.contains(id) {
            Log.p(Log.video, Log.event, "Cleaning up player for video: \(id)")
            // preloadedPlayers[id]?.pause()  // DISABLED PAUSE POINT #2
            preloadedPlayers[id] = nil
            playerSubjects[id]?.send(nil)
            playerSubjects[id] = nil
            videoPositions.removeValue(forKey: id)  // Clean up positions too
        }
    }

    func updateActiveVideos(_ videoId: String) {
        //Unused at the moment
        activeVideoIds.insert(videoId)
    }

    // Add position update method
    func updateVideoPosition(for videoId: String, position: CMTime) {
        videoPositions[videoId] = position
    }
}

struct UnifiedVideoFeed: View {
    @StateObject private var handler = UnifiedVideoHandler.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if handler.videos.isEmpty {
                    emptyStateView
                } else {
                    TabView(selection: $handler.currentIndex) {
                        ForEach(handler.videos.indices, id: \.self) { index in
                            UnifiedVideoPlayer(
                                video: handler.videos[index],
                                player: handler.getPlayer(for: handler.videos[index]),
                                size: geometry.size
                            )
                            .id(handler.videos[index].id)
                            .tag(index)
                            .scrollTargetLayout()
                            .onAppear {
                                Log.p(Log.video, Log.event, "Video player appeared - Index: \(index), ID: \(handler.videos[index].id)")
                            }
                            .onDisappear {
                                Log.p(Log.video, Log.event, "Video player disappeared - Index: \(index), ID: \(handler.videos[index].id)")
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .scrollTargetBehavior(.viewAligned)
                    .ignoresSafeArea()
                    .onChange(of: handler.currentIndex) { oldValue, newValue in
                        Log.p(Log.video, Log.event, "Tab index changed from: \(oldValue) to: \(newValue)")
                        handler.handleIndexChange(newValue)
                    }
                }
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

struct UnifiedVideoPlayer: View {
    let video: Video
    let size: CGSize
    @State private var player: AVPlayer?
    @State private var showingControls = true
    private var playerPublisher: AnyPublisher<AVPlayer?, Never>
    @StateObject private var subscriptions = SubscriptionHolder()

    init(video: Video, player: AVPlayer?, size: CGSize) {
        self.video = video
        self.size = size
        self.playerPublisher = UnifiedVideoHandler.shared.playerPublisher(for: video.id)
    }

    var body: some View {
        ZStack {
            Color.black

            if let player = player {
                CustomVideoPlayer(player: player)
                    .onAppear(perform: setupPlayerObservations)
                    .onDisappear(perform: cleanupPlayer)
            }

            controlsOverlay
        }
        .onTapGesture {
            showingControls.toggle()
            togglePlayback()
        }
        .onReceive(playerPublisher) { newPlayer in
            self.player = newPlayer
        }
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        if player.rate != 0 {
            player.pause()
        } else {
            player.play()
        }
    }

    private func setupPlayerObservations() {
        guard let player = player else { return }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            // When video ends, clear saved position and restart
            UnifiedVideoHandler.shared.updateVideoPosition(for: video.id, position: .zero)
            player.seek(to: .zero)
            player.play()
        }

        // Add periodic time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            UnifiedVideoHandler.shared.updateVideoPosition(for: video.id, position: time)
        }
    }

    private func cleanupPlayer() {
        // player?.pause()  // DISABLED PAUSE POINT #3
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
    }

    @ViewBuilder
    private var controlsOverlay: some View {
        if showingControls {
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(video.username)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding()

                Spacer()
                
                Button(action: togglePlayback) {
                    Image(systemName: player?.rate != 0 ? "pause.fill" : "play.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

                Spacer()
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Supporting Components

struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        //No need to re-assign the player here
        // uiViewController.player = player // Remove this line.
    }
}

// Helper class to hold subscriptions for the view
class SubscriptionHolder: ObservableObject {
    var cancellables: Set<AnyCancellable> = []
}