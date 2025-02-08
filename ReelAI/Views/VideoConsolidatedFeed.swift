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
    private var isHandlingSwipe = false // Track if we're in the middle of a swipe operation
    private var swipeHandlingTask: Task<Void, Never>? // Keep track of the current swipe handling task

    // Player management
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var preloadTasks: [String: Task<Void, Error>] = [:]
    private var playerSubjects: [String: CurrentValueSubject<AVPlayer?, Never>] = [:]
    var cancellables: Set<AnyCancellable> = []  // For managing Combine subscriptions
    private var initialBatchSize = 8 // Increased from 5 to 8
    private var paginationBatchSize = 5 // Increased from 3 to 5

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var dragOffset = CGSize.zero
    @State private var dragDirection: DragDirection = .none
    @Environment(\.dismiss) private var dismiss
    
    private enum DragDirection {
        case horizontal, vertical, none
    }
    
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
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        // Determine drag direction if not already set
                        if dragDirection == .none {
                            dragDirection = abs(gesture.translation.width) > abs(gesture.translation.height) ? .horizontal : .vertical
                        }
                        
                        // Only handle vertical drags for the shortcut
                        if dragDirection == .vertical {
                            // Only allow downward drag with resistance
                            if gesture.translation.height > 0 {
                                dragOffset = CGSize(
                                    width: 0,
                                    height: gesture.translation.height * 0.5
                                )
                            }
                        }
                    }
                    .onEnded { gesture in
                        let verticalThreshold: CGFloat = 100
                        
                        if dragDirection == .vertical && gesture.translation.height > verticalThreshold {
                            Log.p(Log.video, Log.event, "Detected downward swipe, returning to AI Tools")
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = .zero
                                NotificationCenter.default.post(name: NSNotification.Name("ReturnToAITools"), object: nil)
                            }
                        } else {
                            // Reset position if threshold not met
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = .zero
                            }
                        }
                        
                        // Reset drag direction
                        dragDirection = .none
                    }
            )
        }
        .onAppear {
            Log.p(Log.video, Log.start, "Video feed appeared")
            if let currentVideo = handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex] : nil,
               let player = handler.getPlayer(for: currentVideo) {
                player.play()
            }
        }
        .onDisappear {
            Log.p(Log.video, Log.exit, "Video feed disappeared")
            if let currentVideo = handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex] : nil,
               let player = handler.getPlayer(for: currentVideo) {
                player.pause()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Log.p(Log.video, Log.event, "Scene became active")
                if let currentVideo = handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex] : nil,
                   let player = handler.getPlayer(for: currentVideo) {
                    player.play()
                }
            case .inactive, .background:
                Log.p(Log.video, Log.event, "Scene became \(newPhase == .inactive ? "inactive" : "background")")
                if let currentVideo = handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex] : nil,
                   let player = handler.getPlayer(for: currentVideo) {
                    player.pause()
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
    @State private var showInfo = false
    @State private var hideTask: Task<Void, Never>?
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
                    .onDisappear {
                        cleanupPlayer()
                    }
            }

            // Video info and engagement overlay
            ZStack {
                // Semi-transparent gradient background for text readability
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(showInfo ? 0.7 : 0),
                        Color.black.opacity(showInfo ? 0.4 : 0),
                        Color.clear,
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    // Video info (top)
                    if showInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.title)
                                .font(.title2)
                                .bold()
                            
                            HStack {
                                Text(video.username)
                                    .fontWeight(.medium)
                            }
                            
                            if let description = video.description {
                                Text(description)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.top, 50)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    }

                    Spacer()
                    
                    // Engagement buttons (right)
                    VStack(spacing: 12) {
                        Button(action: { /* Like action */ }) {
                            VStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 30))
                                Text("Like")
                                    .font(.caption)
                            }
                        }
                        
                        Button(action: { /* Dislike action */ }) {
                            VStack(spacing: 4) {
                                Image(systemName: "heart.slash.fill")
                                    .font(.system(size: 30))
                                Text("Dislike")
                                    .font(.caption)
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.trailing, 16)
                    .padding(.bottom, 50)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .animation(.easeInOut, value: showInfo)
        }
        .onTapGesture {
            showInfo.toggle()
            scheduleInfoHide()
        }
        .onReceive(playerPublisher) { newPlayer in
            self.player = newPlayer
        }
    }
    
    private func scheduleInfoHide() {
        // Cancel any existing hide task
        hideTask?.cancel()
        
        // If we're showing info, schedule it to be hidden
        if showInfo {
            hideTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 5 seconds
                if !Task.isCancelled {
                    await MainActor.run {
                        showInfo = false
                    }
                }
            }
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
        guard let player = player else { return }
        
        // Remove observers immediately
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
        
        // Delay the pause check to let the swipe animation complete
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms delay
            
            // Get the current handler state
            let handler = UnifiedVideoHandler.shared
            
            // Only pause if this video is not the current one
            if handler.videos.indices.contains(handler.currentIndex),
               handler.videos[handler.currentIndex].id != video.id {
                player.pause()
                Log.p(Log.video, Log.event, "Delayed pause of non-current video: \(video.id)")
            } else {
                Log.p(Log.video, Log.event, "Skipped pausing current video: \(video.id)")
            }
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