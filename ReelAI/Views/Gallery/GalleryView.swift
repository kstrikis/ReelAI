import AVKit
import Combine
import Photos
import SwiftUI
import UIKit

struct GalleryView: View {
    @StateObject private var viewModel: GalleryViewModel
    @State private var selectedVideo: URL?
    @State private var isVideoPlayerPresented = false
    @State private var showingPublisher = false
    @EnvironmentObject private var authService: AuthenticationService

    init(authService: AuthenticationService) {
        Log.p(Log.video, Log.start, "Initializing GalleryView")
        _viewModel = StateObject(wrappedValue: GalleryViewModel(authService: authService))
    }

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.videos, id: \.self) { videoURL in
                        VideoThumbnailView(
                            videoURL: videoURL,
                            thumbnail: viewModel.thumbnails[videoURL],
                            onTap: {
                                Log.p(Log.video, Log.event, "Opening video player for: \(videoURL.path)")
                                selectedVideo = videoURL
                                isVideoPlayerPresented = true
                            },
                            onPublish: {
                                Log.p(Log.video, Log.event, "Opening publisher for: \(videoURL.path)")
                                selectedVideo = videoURL
                                showingPublisher = true
                            },
                            onDelete: {
                                Log.p(Log.video, Log.delete, "Deleting video at: \(videoURL.path)")
                                Task {
                                    await viewModel.deleteVideo(at: videoURL)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("My Videos")
            .sheet(isPresented: $isVideoPlayerPresented) {
                if let videoURL = selectedVideo {
                    NavigationView {
                        VideoPlayerView(videoURL: videoURL)
                            .navigationBarHidden(true)
                    }
                    .interactiveDismissDisabled()
                }
            }
            .sheet(isPresented: $showingPublisher) {
                if let videoURL = selectedVideo {
                    NavigationView {
                        PublishingView(selectedVideo: videoURL)
                    }
                }
            }
            .onChange(of: isVideoPlayerPresented) { newValue in
                if !newValue {
                    Log.p(Log.video, Log.event, "Video player dismissed")
                    selectedVideo = nil
                }
            }
            .onChange(of: showingPublisher) { newValue in
                if !newValue {
                    // Clean up temporary file if it exists
                    if let url = selectedVideo,
                       url.path.contains(FileManager.default.temporaryDirectory.path) {
                        Log.p(Log.storage, Log.delete, "Cleaning up temporary video file")
                        try? FileManager.default.removeItem(at: url)
                    }
                    selectedVideo = nil
                }
            }
            .onAppear {
                Log.p(Log.video, Log.start, "Loading gallery videos")
                viewModel.loadVideos()
            }
        }
    }
}

struct VideoThumbnailView: View {
    let videoURL: URL
    let thumbnail: UIImage?
    let onTap: () -> Void
    let onPublish: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
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
        .contextMenu {
            Button(action: {
                Log.p(Log.video, Log.event, "Opening publisher from gallery")
                Log.p(Log.video, Log.event, "Video details:")
                Log.p(Log.video, Log.event, "- URL type: \(type(of: videoURL))")
                Log.p(Log.video, Log.event, "- URL scheme: \(videoURL.scheme ?? "nil")")
                Log.p(Log.video, Log.event, "- Is file URL: \(videoURL.isFileURL)")
                Log.p(Log.video, Log.event, "- Full URL: \(videoURL)")
                Log.p(Log.video, Log.event, "- Path: \(videoURL.path)")
                onPublish()
            }) {
                Label("Send to Publisher", systemImage: "square.and.arrow.up")
            }
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
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
                            Log.p(Log.video, Log.start, "Starting video playback")
                            player.play()
                        }
                        .onDisappear {
                            Log.p(Log.video, Log.stop, "Stopping video playback")
                            player.pause()
                        }
                }

                Button(action: {
                    Log.p(Log.video, Log.event, "User closed video player")
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
            Log.p(Log.video, Log.start, "VideoPlayerView initialized with URL: \(videoURL.absoluteString)")
            loadVideo()
        }
    }

    private func loadVideo() {
        Log.p(Log.video, Log.start, "Starting video load process")
        isLoading = true
        loadError = nil

        // First find the PHAsset that matches our URL
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)

        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        Log.p(Log.video, Log.read, "Searching for matching video asset")

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
            Log.p(Log.video, Log.read, Log.error, "Could not find matching video asset")
            loadError = "Could not find video in Photos library"
            isLoading = false
            return
        }

        Log.p(Log.video, Log.read, Log.success, "Found matching video asset")

        // Now request the playable asset
        let videoOptions = PHVideoRequestOptions()
        videoOptions.version = .current
        videoOptions.deliveryMode = .highQualityFormat
        videoOptions.isNetworkAccessAllowed = true

        Log.p(Log.video, Log.read, "Requesting playable video asset")

        Task { @MainActor in
            do {
                let avAsset = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAsset, Error>) in
                    PHImageManager.default().requestAVAsset(
                        forVideo: asset,
                        options: videoOptions
                    ) { avAsset, _, info in
                        if let error = info?[PHImageErrorKey] as? Error {
                            Log.p(Log.video, Log.read, Log.error, "Failed to load video asset: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                        } else if let avAsset {
                            Log.p(Log.video, Log.read, Log.success, "Successfully loaded video asset")
                            continuation.resume(returning: avAsset)
                        } else {
                            Log.p(Log.video, Log.read, Log.error, "No video asset returned")
                            continuation.resume(throwing: NSError(domain: "", code: -1,
                                                               userInfo: [NSLocalizedDescriptionKey: "Failed to load video asset"]))
                        }
                    }
                }

                Log.p(Log.video, Log.event, "Received playable video asset")

                // Preload the asset first
                Log.p(Log.video, Log.read, "Preloading asset keys")
                let assetKeys = ["playable", "tracks", "duration"]
                for key in assetKeys {
                    Log.p(Log.video, Log.read, "Loading asset key: \(key)")
                    _ = try await avAsset.loadValues(forKeys: [key])
                    Log.p(Log.video, Log.read, Log.success, "Loaded asset key: \(key)")
                }

                // Verify the asset is playable
                guard avAsset.isPlayable else {
                    Log.p(Log.video, Log.read, Log.error, "Video is not playable")
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video is not playable"])
                }
                Log.p(Log.video, Log.read, Log.success, "Asset is playable")

                // Create player item
                Log.p(Log.video, Log.event, "Creating player item")
                let playerItem = AVPlayerItem(asset: avAsset)

                // Create and set the player
                Log.p(Log.video, Log.event, "Creating player")
                player = AVPlayer(playerItem: playerItem)
                isLoading = false
                Log.p(Log.video, Log.event, Log.success, "Video player ready")

                // Monitor player item status for debugging
                let observation = playerItem.observe(\.status) { item, _ in
                    Log.p(Log.video, Log.event, "Player item status changed to: \(item.status.rawValue)")
                    if let error = item.error {
                        Log.p(Log.video, Log.event, Log.error, "Player item error: \(error.localizedDescription)")
                    }
                }
                // Keep observation alive
                _ = observation

            } catch {
                Log.p(Log.video, Log.event, Log.error, "Failed to load video: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    Log.p(Log.video, Log.event, Log.error, "Error details:")
                    Log.p(Log.video, Log.event, Log.error, "  - Domain: \(nsError.domain)")
                    Log.p(Log.video, Log.event, Log.error, "  - Code: \(nsError.code)")
                    Log.p(Log.video, Log.event, Log.error, "  - Description: \(nsError.localizedDescription)")
                }
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

class GalleryViewModel: ObservableObject {
    @Published var videos: [URL] = []
    @Published var thumbnails: [URL: UIImage] = [:]

    private let localVideoService = LocalVideoService.shared
    private let authService: AuthenticationService

    init(authService: AuthenticationService) {
        self.authService = authService
    }

    func loadVideos() {
        Log.p(Log.video, Log.start, "Loading all videos from storage")
        videos = localVideoService.getAllVideos()
        Log.p(Log.video, Log.read, "Found \(videos.count) videos")

        for videoURL in videos {
            loadThumbnail(for: videoURL)
        }
        Log.p(Log.video, Log.event, "Initiated thumbnail loading for all videos")
    }

    private func loadThumbnail(for videoURL: URL) {
        Log.p(Log.video, Log.start, "Loading thumbnail for \(videoURL.lastPathComponent)")
        Task { @MainActor in
            // Add a small delay to ensure the video file is fully written
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

            do {
                let thumbnail = try await localVideoService.generateThumbnail(for: videoURL)
                    .async()
                if let thumbnail {
                    thumbnails[videoURL] = thumbnail
                    Log.p(Log.video, Log.event, "Successfully loaded thumbnail for \(videoURL.lastPathComponent)")
                } else {
                    Log.p(Log.video, Log.read, Log.error, "Failed to generate thumbnail for \(videoURL.lastPathComponent)")
                }
            } catch {
                Log.p(Log.video, Log.read, Log.error, "Thumbnail generation error: \(error.localizedDescription)")
            }
        }
    }

    func deleteVideo(at url: URL) async {
        Log.p(Log.video, Log.start, "Starting video deletion process for: \(url.path)")
        
        do {
            try await localVideoService.deleteVideo(at: url)
                .async()
            
            // Update UI
            await MainActor.run {
                // Remove from videos array
                videos.removeAll { $0 == url }
                // Remove thumbnail
                thumbnails.removeValue(forKey: url)
            }
            Log.p(Log.video, Log.event, "Successfully deleted video and updated UI")
        } catch {
            Log.p(Log.video, Log.event, Log.error, "Failed to delete video: \(error.localizedDescription)")
            Log.p(Log.video, Log.read, Log.error, "  - File path: \(url.path)")
            Log.p(Log.video, Log.read, Log.error, "  - Error details: \(error)")
        }
    }
}

extension View {
    func logOnAppear(_ message: String) -> some View {
        onAppear {
            print(message)
        }
    }
}
