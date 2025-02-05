import SwiftUI
import AVKit
import Combine
import UIKit

struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @State private var selectedVideo: URL?
    @State private var isVideoPlayerPresented = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.videos, id: \.self) { videoURL in
                        VideoThumbnailView(videoURL: videoURL, thumbnail: viewModel.thumbnails[videoURL]) {
                            selectedVideo = videoURL
                            isVideoPlayerPresented = true
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("My Videos")
            .fullScreenCover(isPresented: $isVideoPlayerPresented) {
                if let videoURL = selectedVideo {
                    VideoPlayerView(videoURL: videoURL)
                }
            }
            .onAppear {
                viewModel.loadVideos()
            }
        }
    }
}

struct VideoThumbnailView: View {
    let videoURL: URL
    let thumbnail: UIImage?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 200)
                    .overlay(
                        ProgressView()
                    )
            }
        }
    }
}

struct VideoPlayerView: View {
    let videoURL: URL
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .edgesIgnoringSafeArea(.all)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
        }
    }
}

class GalleryViewModel: ObservableObject {
    @Published var videos: [URL] = []
    @Published var thumbnails: [URL: UIImage] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let localVideoService = LocalVideoService.shared
    private let logger = AppLogger.ui
    
    func loadVideos() {
        AppLogger.methodEntry(logger)
        videos = localVideoService.getAllVideos()
        
        for videoURL in videos {
            loadThumbnail(for: videoURL)
        }
        AppLogger.methodExit(logger)
    }
    
    private func loadThumbnail(for videoURL: URL) {
        AppLogger.methodEntry(logger)
        localVideoService.generateThumbnail(for: videoURL)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] thumbnail in
                if let thumbnail = thumbnail {
                    self?.thumbnails[videoURL] = thumbnail
                }
            }
            .store(in: &cancellables)
        AppLogger.methodExit(logger)
    }
} 