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
                let batch = try await FirestoreService.shared.fetchVideoBatch(limit: initialBatchSize) // Fetch initial batch with limit
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
        guard preloadedPlayers[video.id] == nil else { return }

        // Cancel any existing preload task for this video.
        preloadTasks[video.id]?.cancel()

        let task: Task<Void, Error> = Task {
            do {
                Log.p(Log.video, Log.event, "Preloading video: \(video.id)")
                guard let url = try await FirestoreService.shared.getVideoDownloadURL(videoId: video.id) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }

                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: playerItem)

                await MainActor.run {
                    preloadedPlayers[video.id] = player
                    playerSubjects[video.id]?.send(player)
                    // NO auto-play here.  Playback is handled in handleIndexChange.
                    Log.p(Log.video, Log.event, "Successfully preloaded video: \(video.id)")
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Preload failed for \(video.id): \(error)")
                 // Consider setting an error state on the video object itself.
            }
        }

        preloadTasks[video.id] = task
    }
    
    func handleIndexChange(_ newIndex: Int) {
        // Use modulo to wrap the index.  This is the core of infinite scrolling.
        let wrappedIndex = newIndex % videos.count
        
        Log.p(Log.video, Log.event, "Handling index change to \(newIndex). Wrapped index: \(wrappedIndex)")

        // Pause *all* players.
        preloadedPlayers.values.forEach { $0.pause() }

        // Update current index to the *wrapped* index.
        currentIndex = wrappedIndex
        
        //Get and manage video by the *wrapped* index
        let currentVideo = videos[wrappedIndex]
        if let player = preloadedPlayers[currentVideo.id] {
              Log.p(Log.video, Log.event, "Playing existing player for video: \(currentVideo.id)")
              player.seek(to: .zero) // Ensure it starts from the beginning.
              player.play()
          } else {
            Log.p(Log.video, Log.event, "Preloading the current video as we did not find it: \(currentVideo.id)")
              preloadVideo(currentVideo) // Preload if not available.
          }

        // Preload adjacent videos based on *wrapped* indices.
        let adjacentIndices = [wrappedIndex - 1, wrappedIndex + 1]
            .map { $0 % videos.count }  // Wrap adjacent indices too
            .filter { $0 >= 0 && $0 < videos.count } // Ensure within bounds

        for index in adjacentIndices {
            let video = videos[index]
            if preloadedPlayers[video.id] == nil {
                preloadVideo(video)
            }
        }

        cleanupInactivePlayers(around: wrappedIndex) //Cleanup also now uses wrapped index
        
        //Pagination check: Load more if near the end.
        if wrappedIndex >= videos.count - 2 {
            loadMoreVideos()
        }
    }

    private func cleanupInactivePlayers(around index: Int) {
        //Calculate active indices, taking into account wrapping.
        let activeIndices = [index - 1, index, index + 1].map { $0 % videos.count }.filter { $0 >= 0 }
        var activeVideoIds = Set(activeIndices.map { videos[$0].id })

        // Always keep first video loaded.
        if let firstVideoId = videos.first?.id {
            activeVideoIds.insert(firstVideoId)
        }

        // Cancel tasks and remove players for videos that are no longer active.
         for videoId in preloadedPlayers.keys {
             if !activeVideoIds.contains(videoId) {
                 preloadTasks[videoId]?.cancel()
                 preloadTasks[videoId] = nil
                 preloadedPlayers[videoId] = nil
                 playerSubjects[videoId]?.send(nil)  // Important:  Notify subscribers that the player is gone.
                 playerSubjects[videoId] = nil      // Clean up the subject.
             }
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
                    // Use .vertical for PageView
                    PageView(
                        axis: .vertical,
                        pages: handler.videos.indices.map { index in //Use indices for mapping
                            UnifiedVideoPlayer(
                                video: handler.videos[index],
                                player: handler.getPlayer(for: handler.videos[index]),
                                size: geometry.size
                            )
                            .id(index) // Crucial: Use .id(index) for correct identification
                        },
                        currentIndex: $handler.currentIndex
                    )
                    // No .onChange here. PageView handles the index changes internally.
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

// Custom PageView implementation
struct PageView<Content: View>: View {
    let axis: Axis
    let pages: [Content]
    @Binding var currentIndex: Int
    @State private var scrollPosition: Int? // Use scrollPosition for the value

    var body: some View {
        ScrollView(axis == .vertical ? .vertical : .horizontal, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    pages[index]
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .id(index) // Use id for scroll target
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollPosition) // Use scrollPosition modifier
        .onChange(of: scrollPosition) { oldValue, newValue in
            if let newValue = newValue, newValue != currentIndex {
                DispatchQueue.main.async {
                    UnifiedVideoHandler.shared.handleIndexChange(newValue)
                }
            }
        }
        .onAppear {
            //Initial setting
            self.scrollPosition = currentIndex
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

// MARK: - Firestore Service (Modified for Pagination)

extension FirestoreService {
    
    //Adds optional starting point and limits
    func fetchVideoBatch(startingAfter lastVideo: Video? = nil, limit: Int) async throws -> [Video] {
        let videosCollection = Firestore.firestore().collection("videos")
        var query: Query = videosCollection.order(by: "createdAt", descending: true).limit(to: limit) // Order by creation date.

        // If a starting video is provided, start the query after it.
        if let lastVideo = lastVideo {
            query = query.start(afterDocument: try await Firestore.firestore().collection("videos").document(lastVideo.id).getDocument())
        }

        let snapshot = try await query.getDocuments()
        let videos: [Video] = snapshot.documents.compactMap { document in
            do {
                let video = try document.data(as: Video.self)
                return video
            } catch {
                Log.p(Log.firebase, Log.read, Log.error, "Error decoding video: \(error)")
                return nil
            }
        }
        return videos
    }
}