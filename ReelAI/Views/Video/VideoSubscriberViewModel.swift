import SwiftUI
import AVKit
import Combine

@MainActor
class VideoSubscriberViewModel: ObservableObject {
    @Published var player: AVPlayer?
    
    init(video: Video) {
        // Directly subscribe to player updates from VideoFeedViewModel
        VideoFeedViewModel.shared?.playerPublisher(for: video.id)
            .receive(on: DispatchQueue.main)
            .assign(to: &$player)
    }
} 