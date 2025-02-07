import SwiftUI
import AVKit
import Combine

@MainActor
class VideoSubscriberViewModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var state = VideoState.loading
    
    private var cancellables = Set<AnyCancellable>()
    private let video: Video
    
    enum VideoState: Equatable {
        case loading
        case ready
        case failed(String)
    }
    
    init(video: Video) {
        Log.p(Log.video, Log.start, "Initializing video subscriber for video: \(video.id)")
        self.video = video
        subscribeToPlayer()
    }
    
    private func subscribeToPlayer() {
        guard let feedViewModel = VideoFeedViewModel.shared else {
            Log.p(Log.video, Log.event, Log.error, "No VideoFeedViewModel available")
            state = .failed("Feed unavailable")
            return
        }
        
        // Subscribe to player updates for this video
        feedViewModel.playerPublisher(for: video.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] player in
                guard let self = self else { return }
                Log.p(Log.video, Log.event, "Received player update for video: \(video.id)")
                
                if let player = player {
                    self.player = player
                    self.state = .ready
                } else {
                    self.player = nil
                    self.state = .loading
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        Log.p(Log.video, Log.exit, "VideoSubscriberViewModel deinit for video: \(video.id)")
        cancellables.removeAll()
    }
} 