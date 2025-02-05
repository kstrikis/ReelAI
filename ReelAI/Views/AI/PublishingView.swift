import SwiftUI
import PhotosUI
import Combine
import AVKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct PublishingView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PublishingViewModel
    
    init(selectedVideo: URL? = nil) {
        // We need to use a temporary AuthenticationService here, it will be replaced by the environment object
        let tempAuthService = AuthenticationService()
        _viewModel = StateObject(wrappedValue: PublishingViewModel(preselectedVideo: selectedVideo, authService: tempAuthService))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Video Selection
                    if let selectedVideo = viewModel.selectedVideo {
                        VideoPreview(url: selectedVideo)
                            .frame(height: 200)
                            .cornerRadius(12)
                    } else {
                        VideoSelectionButton(action: viewModel.showVideoPicker)
                    }
                    
                    // Title and Description
                    CustomTextField(
                        placeholder: "Title",
                        text: Binding(
                            get: { viewModel.title },
                            set: { viewModel.handleTitleEdit($0) }
                        )
                    )
                    
                    // Description using TextEditor for multiline support
                    TextEditor(text: $viewModel.description)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            Group {
                                if viewModel.description.isEmpty {
                                    Text("Description")
                                        .foregroundColor(.gray.opacity(0.7))
                                        .padding(.leading, 12)
                                        .padding(.top, 12)
                                }
                            },
                            alignment: .topLeading
                        )
                    
                    // Upload Button
                    if viewModel.isUploading {
                        VStack {
                            Text(viewModel.publishState)
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            Button("Cancel", role: .destructive) {
                                viewModel.cancelUpload()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    } else {
                        Button(action: {
                            if let userId = authService.currentUser?.uid,
                               let username = authService.userProfile?.username {
                                viewModel.uploadVideo(userId: userId, username: username)
                            }
                        }) {
                            Text("Publish")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!viewModel.canUpload)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Publish")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $viewModel.showingVideoPicker,
                     selection: $viewModel.videoSelection,
                     matching: .videos)
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .alert("Success", isPresented: $viewModel.showingSuccess) {
            Button("Done", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Your video has been uploaded successfully!")
        }
        .onAppear {
            // Update the viewModel's authService with the one from the environment
            viewModel.updateAuthService(authService)
        }
    }
}

struct VideoSelectionButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 40))
                Text("Select Video")
                    .font(.headline)
                Text("Tap to choose a video from your library")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
        }
        .foregroundColor(.white)
    }
}

struct VideoPreview: View {
    let url: URL
    @State private var player: AVPlayer?
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
            } else {
                ProgressView("Loading video...")
            }
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func loadVideo() {
        print("🎥 🔍 VIDEO PREVIEW - Loading video from URL: \(url)")
        print("🎥 🔍 VIDEO PREVIEW - URL scheme: \(url.scheme ?? "nil")")
        print("🎥 🔍 VIDEO PREVIEW - Is file URL: \(url.isFileURL)")
        print("🎥 🔍 VIDEO PREVIEW - Path: \(url.path)")
        
        // If it's a file URL (from manual selection), use it directly
        if url.isFileURL {
            print("🎥 📂 VIDEO PREVIEW - Using direct file access")
            let playerItem = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: playerItem)
            self.player?.play()
            return
        }
        
        // Otherwise, try to find it in Photos library
        print("🎥 📱 VIDEO PREVIEW - Searching Photos library")
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        print("🎥 📱 VIDEO PREVIEW - Found \(fetchResult.count) videos in Photos")
        
        fetchResult.enumerateObjects { asset, _, stop in
            print("🎥 📱 VIDEO PREVIEW - Checking asset: \(asset.localIdentifier)")
            let videoOptions = PHVideoRequestOptions()
            videoOptions.version = .current
            videoOptions.deliveryMode = .highQualityFormat
            videoOptions.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    let assetURL = urlAsset.url
                    print("🎥 📱 VIDEO PREVIEW - Comparing asset URL: \(assetURL.lastPathComponent)")
                    print("🎥 📱 VIDEO PREVIEW - With target URL: \(url.lastPathComponent)")
                    if assetURL.lastPathComponent == url.lastPathComponent {
                        print("🎥 ✅ VIDEO PREVIEW - Found matching video!")
                        DispatchQueue.main.async {
                            let playerItem = AVPlayerItem(asset: urlAsset)
                            self.player = AVPlayer(playerItem: playerItem)
                            self.player?.play()
                        }
                        stop.pointee = true
                    }
                } else {
                    print("🎥 ❌ VIDEO PREVIEW - Asset is not a URL asset")
                }
            }
        }
    }
}

class PublishingViewModel: ObservableObject {
    @Published var title = ""
    @Published var description = ""
    @Published var selectedVideo: URL?
    @Published var showingVideoPicker = false
    @Published var videoSelection: PhotosPickerItem? {
        didSet { handleVideoSelection() }
    }
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var showingError = false
    @Published var errorMessage: String?
    @Published var showingSuccess = false
    @Published var publishState: String = ""
    
    private var hasEditedTitle = false
    private var cancellables = Set<AnyCancellable>()
    private var authService: AuthenticationService
    
    init(preselectedVideo: URL? = nil, authService: AuthenticationService) {
        self.authService = authService
        print("📤 PublishingViewModel init")
        print("📤 Preselected video URL: \(String(describing: preselectedVideo))")
        
        // Set default title as current date/time
        updateDefaultTitle()
        
        // If we have a preselected video, load it
        if let preselectedVideo {
            print("📤 Loading preselected video: \(preselectedVideo.path)")
            loadVideoFromURL(preselectedVideo)
        }
    }
    
    private func updateDefaultTitle() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        title = formatter.string(from: Date())
    }
    
    var effectiveTitle: String {
        // If title has been edited and is empty, return empty string (will fail validation)
        // Otherwise return either the edited title or the default title
        hasEditedTitle && title.isEmpty ? "" : title
    }
    
    var canUpload: Bool {
        !effectiveTitle.isEmpty && selectedVideo != nil
    }
    
    func handleTitleEdit(_ newTitle: String) {
        hasEditedTitle = true
        title = newTitle
    }
    
    func showVideoPicker() {
        showingVideoPicker = true
    }
    
    private func handleVideoSelection() {
        guard let selection = videoSelection else { return }
        
        Task {
            do {
                let videoData = try await selection.loadTransferable(type: Data.self)
                guard let videoData = videoData else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load video data"])
                }
                
                // Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try videoData.write(to: tempURL)
                
                await MainActor.run {
                    self.selectedVideo = tempURL
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                }
            }
        }
    }
    
    private func loadVideoFromURL(_ url: URL) {
        Task {
            do {
                // If it's already in our sandbox, use it directly
                if url.path.contains(FileManager.default.temporaryDirectory.path) {
                    await MainActor.run {
                        self.selectedVideo = url
                    }
                    return
                }
                
                // Otherwise, load it through Photos framework
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
                let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
                
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
                            if assetURL.lastPathComponent == url.lastPathComponent {
                                foundAsset = asset
                                stop.pointee = true
                            }
                        }
                    }
                    dispatchGroup.wait()
                }
                
                guard let asset = foundAsset else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find video in Photos library"])
                }
                
                // Request the video data
                let videoOptions = PHVideoRequestOptions()
                videoOptions.version = .current
                videoOptions.deliveryMode = .highQualityFormat
                videoOptions.isNetworkAccessAllowed = true
                
                let avAsset = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAsset, Error>) in
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, info in
                        if let error = info?[PHImageErrorKey] as? Error {
                            continuation.resume(throwing: error)
                        } else if let avAsset {
                            continuation.resume(returning: avAsset)
                        } else {
                            continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video"]))
                        }
                    }
                }
                
                guard let urlAsset = avAsset as? AVURLAsset else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get URL from asset"])
                }
                
                // Create a temporary copy in our sandbox
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try FileManager.default.copyItem(at: urlAsset.url, to: tempURL)
                
                await MainActor.run {
                    self.selectedVideo = tempURL
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                }
            }
        }
    }
    
    func uploadVideo(userId: String, username: String) {
        print("📤 Starting upload process...")
        print("📤 Selected video URL: \(String(describing: selectedVideo))")
        
        guard let videoURL = selectedVideo else {
            print("❌ No video URL available")
            errorMessage = "No video selected"
            showingError = true
            return
        }
        print("📤 Video exists at: \(videoURL.path)")
        
        guard !effectiveTitle.isEmpty else {
            print("❌ No title provided")
            errorMessage = "Title is required"
            showingError = true
            return
        }
        print("📤 Title: \(effectiveTitle)")
        
        isUploading = true
        publishState = "Preparing..."
        
        VideoService.shared.publishVideo(
            url: videoURL,
            userId: userId,
            username: username,
            title: effectiveTitle,
            description: description.isEmpty ? nil : description
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .creatingDocument:
                self.publishState = "Creating document..."
                
            case let .uploading(progress):
                self.uploadProgress = progress
                self.publishState = "Uploading video: \(Int(progress * 100))%"
                
            case .updatingDocument:
                self.publishState = "Finalizing..."
                
            case .completed:
                self.isUploading = false
                self.showingSuccess = true
                self.publishState = ""
                
            case let .error(error):
                self.isUploading = false
                self.errorMessage = error.localizedDescription
                self.showingError = true
                self.publishState = ""
            }
        }
        .store(in: &cancellables)
    }
    
    func updateAuthService(_ newAuthService: AuthenticationService) {
        print("📤 Updating auth service")
        self.authService = newAuthService
    }
    
    func cancelUpload() {
        cancellables.removeAll()
        isUploading = false
        uploadProgress = 0
        publishState = ""
    }
}

#Preview {
    NavigationView {
        PublishingView()
            .environmentObject(AuthenticationService.preview)
    }
} 