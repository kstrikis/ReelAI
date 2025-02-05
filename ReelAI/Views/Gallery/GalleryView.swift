import AVKit
import Combine
import Photos
import SwiftUI
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
        GridItem(.adaptive(minimum: 150), spacing: 16),
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
            .onChange(of: isVideoPlayerPresented) { isPresented in
                print("🎥 📝 Video player sheet isPresented changed to: \(isPresented)")
                print("🎥 📝 Selected video URL: \(selectedVideo?.absoluteString ?? "nil")")
            }
            .sheet(isPresented: $isVideoPlayerPresented, onDismiss: {
                print("🎥 📝 Video player sheet dismissed")
                // Don't clear selectedVideo here
            }) {
                Group {
                    if let videoURL = selectedVideo {
                        NavigationView {
                            VideoPlayerView(videoURL: videoURL)
                                .navigationBarHidden(true)
                                .onAppear {
                                    print("🎥 📝 VideoPlayerView onAppear called")
                                }
                                .onDisappear {
                                    print("🎥 📝 VideoPlayerView onDisappear called")
                                    // Clear selectedVideo only when the view actually disappears
                                    selectedVideo = nil
                                }
                        }
                        .interactiveDismissDisabled()
                        .logOnAppear("🎥 📝 Creating video player sheet with URL: \(videoURL.absoluteString)")
                    } else {
                        Text("No video selected")
                            .foregroundColor(.red)
                            .onAppear {
                                print("❌ 🚫 Sheet presented with no video selected")
                            }
                    }
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
        Button(action: {
            print("🎥 👆 Video thumbnail tapped: \(videoURL.lastPathComponent)")
            onTap()
        }) {
            if let thumbnail {
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
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                if let error = loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.yellow)
                        Text(error)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if isLoading {
                    ProgressView("Loading video...")
                        .foregroundColor(.white)
                } else if let player {
                    VideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            print("🎥 ▶️ Starting video playback")
                            player.play()
                        }
                        .onDisappear {
                            print("🎥 ⏹️ Stopping video playback")
                            player.pause()
                        }
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
        }
        .onAppear {
            print("🎥 🎬 VideoPlayerView initialized with URL: \(videoURL.absoluteString)")
            loadVideo()
        }
    }

    private func loadVideo() {
        print("🎥 🔄 Starting video load process")
        isLoading = true
        loadError = nil

        // First find the PHAsset that matches our URL
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)

        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        print("🎥 🔍 Searching for matching video asset...")

        var foundAsset: PHAsset?
        fetchResult.enumerateObjects { asset, _, stop in
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()

            let videoOptions = PHVideoRequestOptions()
            videoOptions.version = .current
            videoOptions.deliveryMode = .highQualityFormat
            videoOptions.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
                defer { dispatchGroup.leave() }
                if let urlAsset = avAsset as? AVURLAsset {
                    let assetURL = urlAsset.url
                    if assetURL.lastPathComponent == videoURL.lastPathComponent {
                        foundAsset = asset
                        stop.pointee = true
                    }
                }
            }

            dispatchGroup.wait()
        }

        guard let asset = foundAsset else {
            print("❌ 🚫 Could not find matching video asset")
            loadError = "Could not find video in Photos library"
            isLoading = false
            return
        }

        print("🎥 ✅ Found matching video asset")

        // Now request the playable asset
        let videoOptions = PHVideoRequestOptions()
        videoOptions.version = .current
        videoOptions.deliveryMode = .highQualityFormat
        videoOptions.isNetworkAccessAllowed = true

        print("🎥 🔍 Requesting playable video asset...")

        Task { @MainActor in
            do {
                let avAsset = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAsset, Error>) in
                    PHImageManager.default().requestAVAsset(
                        forVideo: asset,
                        options: videoOptions
                    ) { avAsset, _, info in
                        if let error = info?[PHImageErrorKey] as? Error {
                            continuation.resume(throwing: error)
                        } else if let avAsset {
                            continuation.resume(returning: avAsset)
                        } else {
                            continuation.resume(throwing: NSError(domain: "", code: -1,
                                                                  userInfo: [NSLocalizedDescriptionKey: "Failed to load video asset"]))
                        }
                    }
                }

                print("🎥 ✅ Received playable video asset")

                // Preload the asset first
                print("🎥 🔍 Preloading asset...")
                let assetKeys = ["playable", "tracks", "duration"]
                for key in assetKeys {
                    print("🎥 🔍 Loading asset key: \(key)")
                    _ = try await avAsset.loadValues(forKeys: [key])
                    print("🎥 ✅ Loaded asset key: \(key)")
                }

                // Verify the asset is playable
                guard avAsset.isPlayable else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video is not playable"])
                }
                print("🎥 ✅ Asset is playable")

                // Create player item
                print("🎥 ⚙️ Creating player item...")
                let playerItem = AVPlayerItem(asset: avAsset)

                // Create and set the player immediately
                print("🎥 ⚙️ Creating player...")
                player = AVPlayer(playerItem: playerItem)
                print("🎥 ✅ Video loaded successfully")
                isLoading = false

                // Monitor player item status for debugging
                let observation = playerItem.observe(\.status) { item, _ in
                    print("🎥 📊 Player item status changed to: \(item.status.rawValue)")
                    if let error = item.error {
                        print("❌ 💥 Player item error: \(error.localizedDescription)")
                    }
                }
                // Keep observation alive
                _ = observation

            } catch {
                print("❌ 💥 Failed to load video: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("❌ 💥 Error details:")
                    print("  - Domain: \(nsError.domain)")
                    print("  - Code: \(nsError.code)")
                    print("  - Description: \(nsError.localizedDescription)")
                }
                loadError = "Failed to load video: \(error.localizedDescription)"
                isLoading = false
            }
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
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

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

extension View {
    func logOnAppear(_ message: String) -> some View {
        onAppear {
            print(message)
        }
    }
}
