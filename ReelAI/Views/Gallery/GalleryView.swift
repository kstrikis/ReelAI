import SwiftUI
import AVKit
import Combine
import UIKit

struct GalleryView: View {
    @StateObject private var viewModel: GalleryViewModel
    @State private var selectedVideo: URL?
    @State private var isVideoPlayerPresented = false
    @State private var showingUploadAlert = false
    @EnvironmentObject private var authService: AuthenticationService
    
    init(authService: AuthenticationService) {
        _viewModel = StateObject(wrappedValue: GalleryViewModel(authService: authService))
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                if viewModel.isUploading {
                    ProgressView("Uploading... \(Int((viewModel.uploadProgress ?? 0) * 100))%")
                        .padding()
                }
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.videos, id: \.self) { videoURL in
                        VideoThumbnailView(videoURL: videoURL, thumbnail: viewModel.thumbnails[videoURL]) {
                            selectedVideo = videoURL
                            isVideoPlayerPresented = true
                        }
                        .onLongPressGesture {
                            selectedVideo = videoURL
                            showingUploadAlert = true
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("My Videos")
            .sheet(isPresented: $isVideoPlayerPresented) {
                if let videoURL = selectedVideo {
                    VideoPlayerView(videoURL: videoURL)
                }
            }
            .alert("Upload Video", isPresented: $showingUploadAlert) {
                Button("Upload", role: .none) {
                    if let videoURL = selectedVideo {
                        Task {
                            await viewModel.uploadVideo(at: videoURL)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Would you like to upload this video to the cloud?")
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
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let player = player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        print("🎥 ▶️ Starting video playback")
                        player.play()
                    }
                    .onDisappear {
                        print("🎥 ⏹️ Stopping video playback")
                        player.pause()
                    }
            } else {
                ProgressView("Loading video...")
                    .foregroundColor(.white)
            }
            
            Button(action: {
                print("🎥 🚪 Closing video player")
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            print("🎥 🔍 Loading video from: \(videoURL.absoluteString)")
            let asset = AVURLAsset(url: videoURL)
            let playerItem = AVPlayerItem(asset: asset)
            self.player = AVPlayer(playerItem: playerItem)
        }
    }
}

class GalleryViewModel: ObservableObject {
    @Published var videos: [URL] = []
    @Published var thumbnails: [URL: UIImage] = [:]
    @Published var isUploading = false
    @Published var uploadProgress: Double?
    
    private var cancellables = Set<AnyCancellable>()
    private let localVideoService = LocalVideoService.shared
    private let uploadService = VideoUploadService.shared
    private let authService: AuthenticationService
    
    init(authService: AuthenticationService) {
        self.authService = authService
    }
    
    func loadVideos() {
        print("🖼️ 🔄 Loading all videos from storage")
        videos = localVideoService.getAllVideos()
        print("🖼️ 📝 Found \(videos.count) videos")
        
        for videoURL in videos {
            loadThumbnail(for: videoURL)
        }
        print("🖼️ ✅ Initiated thumbnail loading for all videos")
    }
    
    private func loadThumbnail(for videoURL: URL) {
        print("🖼️ 🖼️ Loading thumbnail for \(videoURL.lastPathComponent)")
        Task { @MainActor in
            // Add a small delay to ensure the video file is fully written
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second delay
            
            do {
                let thumbnail = try await localVideoService.generateThumbnail(for: videoURL)
                    .async()
                if let thumbnail {
                    thumbnails[videoURL] = thumbnail
                    print("🖼️ ✅ Successfully loaded thumbnail for \(videoURL.lastPathComponent)")
                } else {
                    print("❌ 🚫 Failed to generate thumbnail for \(videoURL.lastPathComponent)")
                }
            } catch {
                print("❌ 💥 Thumbnail generation error: \(error.localizedDescription)")
            }
        }
    }
    
    func uploadVideo(at url: URL) async {
        print("🖼️ 📤 Starting video upload process")
        guard let userId = authService.currentUser?.uid else {
            print("❌ 🔒 Upload failed: User not authenticated")
            return
        }
        
        print("🖼️ 🎬 Beginning upload for video: \(url.lastPathComponent)")
        isUploading = true
        uploadProgress = 0
        
        uploadService.uploadVideo(at: url, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case let .progress(progress):
                    print("🖼️ 📊 Upload progress: \(Int(progress * 100))%")
                    self?.uploadProgress = progress
                case .completed:
                    print("🖼️ ✅ Upload completed successfully")
                    self?.isUploading = false
                    self?.uploadProgress = nil
                case let .failure(error):
                    print("❌ 💥 Upload failed: \(error.localizedDescription)")
                    self?.isUploading = false
                    self?.uploadProgress = nil
                }
            }
            .store(in: &cancellables)
    }
} 