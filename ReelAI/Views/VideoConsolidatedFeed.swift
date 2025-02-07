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

    private init() {
        loadInitialVideos()
    }

    func loadInitialVideos() {
        Log.p(Log.video, Log.event, "Loading initial batch of videos")

        isLoading = true
        Task {
            do {
                // Use the existing FirestoreService
                let initialCheck = try await FirestoreService.shared.fetchVideoBatch(startingAfter: nil, limit: 1)
                if initialCheck.isEmpty {
                    Log.p(Log.video, Log.event, "No videos found, attempting to seed...")
                    try await FirestoreService.shared.seedVideos()
                }

                let batch = try await FirestoreService.shared.fetchVideoBatch(startingAfter: nil, limit: initialBatchSize)
                Log.p(Log.video, Log.event, "Received \(batch.count) videos")

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
                   guard let lastVideo = videos.last else {
                       // No videos to paginate from, shouldn't happen normally.
                       isLoading = false
                       return
                   }

                   let newVideos = try await FirestoreService.shared.fetchVideoBatch(startingAfter: lastVideo, limit: paginationBatchSize)
                   Log.p(Log.video, Log.event, "Fetched \(newVideos.count) more videos")
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

        let task: Task<Void, Error> = Task {
            do {
                Log.p(Log.video, Log.event, "Preloading video: \(id)")
                // Use FirestoreService to get the URL.
                guard let url = try await FirestoreService.shared.getVideoDownloadURL(videoId: id) else {
                    Log.p(Log.video, Log.event, Log.error, "Failed to get download URL for \(id)")
                    return // Exit gracefully if no URL.
                }

                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: playerItem)

                await MainActor.run {
                    preloadedPlayers[id] = player
                    playerSubjects[id]?.send(player)
                    Log.p(Log.video, Log.event, "Successfully preloaded video: \(id)")
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Preload failed for \(id): \(error)")
            }
        }

        preloadTasks[id] = task
    }

    func handleIndexChange(_ newIndex: Int) {
        Log.p(Log.video, Log.event, "Beginning index change handling - New Index: \(newIndex)")
        
        // Validate index bounds
        guard newIndex >= 0 && newIndex < videos.count else {
            Log.p(Log.video, Log.event, Log.error, "Invalid index: \(newIndex), videos count: \(videos.count)")
            return
        }

        // Pause all existing players first
        for (id, player) in preloadedPlayers {
            player.pause()
            Log.p(Log.video, Log.event, "Paused player for video: \(id)")
        }

        // Update current index
        currentIndex = newIndex
        Log.p(Log.video, Log.event, "Updated current index to: \(newIndex)")

        // Handle current video
        let currentVideo = videos[newIndex]
        let currentId = currentVideo.id
        
        if let player = preloadedPlayers[currentId] {
            Log.p(Log.video, Log.event, "Playing existing player for current video: \(currentId)")
            player.seek(to: .zero)
            player.play()
        } else {
            Log.p(Log.video, Log.event, "Preloading current video: \(currentId)")
            preloadVideo(currentVideo)
        }

        // Calculate and preload adjacent videos
        let preloadIndices = Set([
            max(0, newIndex - 1),
            newIndex,
            min(videos.count - 1, newIndex + 1)
        ])
        
        Log.p(Log.video, Log.event, "Preloading indices: \(preloadIndices)")
        
        for index in preloadIndices {
            let video = videos[index]
            if preloadedPlayers[video.id] == nil {
                preloadVideo(video)
            }
        }

        // Cleanup inactive players
        cleanupInactivePlayers(around: newIndex)

        // Check for pagination
        if newIndex >= videos.count - 2 {
            Log.p(Log.video, Log.event, "Near end of list, triggering pagination")
            loadMoreVideos()
        }
    }

    private func cleanupInactivePlayers(around index: Int) {
        let keepIndices = Set([
            max(0, index - 1),
            index,
            min(videos.count - 1, index + 1)
        ])
        
        var keepIds = Set(keepIndices.map { videos[$0].id })
        Log.p(Log.video, Log.event, "Keeping video IDs: \(keepIds)")

        // Always keep first video
        if let firstId = videos.first?.id {
            keepIds.insert(firstId)
        }

        // Remove players not in keepIds
        for id in preloadedPlayers.keys where !keepIds.contains(id) {
            preloadedPlayers[id]?.pause()
            preloadedPlayers[id] = nil
            preloadTasks[id]?.cancel()
            preloadTasks[id] = nil
            playerSubjects[id]?.send(nil)
            playerSubjects[id] = nil
            Log.p(Log.video, Log.event, "Cleaned up player for video: \(id)")
        }
    }

    func updateActiveVideos(_ videoId: String) {
        //Unused at the moment
        activeVideoIds.insert(videoId)
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
                            .id(handler.videos[index].id) // Use video ID for stable identity
                            .tag(index)
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
    @State private var player: AVPlayer? // Observe changes to the player.
    @State private var showingControls = true
    @State private var isPlaying = false // Local state to track play/pause.
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
            if let player = player {
                if isPlaying {
                    player.pause()
                } else {
                    player.play()
                }
                isPlaying.toggle() // Toggle the local play/pause state.
            }

        }
        .onReceive(playerPublisher) { newPlayer in
            //Crucial: listen to player changes published by UnifiedVideoHandler
            self.player = newPlayer
        }
    }

    private func setupPlayerObservations() {
        guard let player = player else { return }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
            isPlaying = true
        }

        // Store in our own cancellables instead of UnifiedVideoHandler's
        player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { [weak player] newRate in
                guard let player = player else { return }
                isPlaying = (newRate != 0 && player.error == nil)
            }
            .store(in: &subscriptions.cancellables)
    }

    private func cleanupPlayer() {
        player?.pause()
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
                // Play/Pause Button (Optional, but good for clarity)
                Button(action: {
                    if let player = player {
                         if isPlaying {
                             player.pause()
                         } else {
                             player.play()
                         }
                         isPlaying.toggle() // Toggle local play/pause state
                     }
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
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