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
        Log.p(Log.video, Log.start, "Initializing PublishingView")
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
        Log.p(Log.video, Log.start, "Loading video preview")
        Log.p(Log.video, Log.event, "Video details:")
        Log.p(Log.video, Log.event, "- URL: \(url)")
        Log.p(Log.video, Log.event, "- Scheme: \(url.scheme ?? "nil")")
        Log.p(Log.video, Log.event, "- Is file URL: \(url.isFileURL)")
        Log.p(Log.video, Log.event, "- Path: \(url.path)")
        
        // If it's a file URL (from manual selection), use it directly
        if url.isFileURL {
            Log.p(Log.video, Log.read, "Using direct file access")
            let playerItem = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: playerItem)
            self.player?.play()
            return
        }
        
        // Otherwise, try to find it in Photos library
        Log.p(Log.video, Log.read, "Searching Photos library")
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        Log.p(Log.video, Log.read, "Found \(fetchResult.count) videos in Photos")
        
        fetchResult.enumerateObjects { asset, _, stop in
            Log.p(Log.video, Log.read, "Checking asset: \(asset.localIdentifier)")
            let videoOptions = PHVideoRequestOptions()
            videoOptions.version = .current
            videoOptions.deliveryMode = .highQualityFormat
            videoOptions.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    let assetURL = urlAsset.url
                    Log.p(Log.video, Log.read, "Comparing URLs:")
                    Log.p(Log.video, Log.read, "- Asset: \(assetURL.lastPathComponent)")
                    Log.p(Log.video, Log.read, "- Target: \(url.lastPathComponent)")
                    if assetURL.lastPathComponent == url.lastPathComponent {
                        Log.p(Log.video, Log.read, Log.success, "Found matching video")
                        DispatchQueue.main.async {
                            let playerItem = AVPlayerItem(asset: urlAsset)
                            self.player = AVPlayer(playerItem: playerItem)
                            self.player?.play()
                        }
                        stop.pointee = true
                    }
                } else {
                    Log.p(Log.video, Log.read, Log.error, "Asset is not a URL asset")
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
    private var uploadTask: Task<Void, Error>?
    
    init(preselectedVideo: URL? = nil, authService: AuthenticationService) {
        self.authService = authService
        Log.p(Log.video, Log.start, "Initializing PublishingViewModel")
        Log.p(Log.video, Log.event, "Preselected video URL: \(String(describing: preselectedVideo))")
        
        // Set default title as current date/time
        updateDefaultTitle()
        
        // If we have a preselected video, load it
        if let preselectedVideo {
            Log.p(Log.video, Log.read, "Loading preselected video: \(preselectedVideo.path)")
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
        !effectiveTitle.isEmpty && selectedVideo != nil && !isUploading
    }
    
    func handleTitleEdit(_ newTitle: String) {
        hasEditedTitle = true
        title = newTitle
    }
    
    func showVideoPicker() {
        Log.p(Log.video, Log.event, "Showing video picker")
        showingVideoPicker = true
    }
    
    private func handleVideoSelection() {
        guard let item = videoSelection else { return }
        
        Log.p(Log.video, Log.start, "Processing selected video")
        
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    Log.p(Log.video, Log.event, Log.error, "Selected video data is nil")
                    return
                }
                
                // Create a temporary URL
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                
                // Write the data
                try data.write(to: tempURL)
                Log.p(Log.video, Log.save, Log.success, "Saved video to temporary location: \(tempURL.path)")
                
                // Update UI on main thread
                await MainActor.run {
                    loadVideoFromURL(tempURL)
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Failed to load selected video: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = "Failed to load video: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
    
    private func loadVideoFromURL(_ url: URL) {
        Log.p(Log.video, Log.read, "Loading video from URL: \(url.path)")
        
        Task {
            do {
                // If it's already in our sandbox, use it directly
                if url.path.contains(FileManager.default.temporaryDirectory.path) {
                    Log.p(Log.video, Log.read, "Using direct file access for temporary file")
                    await MainActor.run {
                        self.selectedVideo = url
                    }
                    return
                }
                
                // Otherwise, load it through Photos framework
                Log.p(Log.video, Log.read, "Searching Photos library for video")
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
                let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
                Log.p(Log.video, Log.read, "Found \(fetchResult.count) videos in Photos")
                
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
                            Log.p(Log.video, Log.read, "Comparing URLs:")
                            Log.p(Log.video, Log.read, "- Asset: \(assetURL.lastPathComponent)")
                            Log.p(Log.video, Log.read, "- Target: \(url.lastPathComponent)")
                            if assetURL.lastPathComponent == url.lastPathComponent {
                                foundAsset = asset
                                stop.pointee = true
                            }
                        }
                    }
                    dispatchGroup.wait()
                }
                
                guard let asset = foundAsset else {
                    Log.p(Log.video, Log.read, Log.error, "Could not find video in Photos library")
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find video in Photos library"])
                }
                
                Log.p(Log.video, Log.read, Log.success, "Found matching video asset")
                
                // Request the video data
                let videoOptions = PHVideoRequestOptions()
                videoOptions.version = .current
                videoOptions.deliveryMode = .highQualityFormat
                videoOptions.isNetworkAccessAllowed = true
                
                Log.p(Log.video, Log.read, "Requesting video asset")
                let avAsset = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAsset, Error>) in
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, info in
                        if let error = info?[PHImageErrorKey] as? Error {
                            Log.p(Log.video, Log.read, Log.error, "Failed to load video asset: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                        } else if let avAsset {
                            Log.p(Log.video, Log.read, Log.success, "Successfully loaded video asset")
                            continuation.resume(returning: avAsset)
                        } else {
                            Log.p(Log.video, Log.read, Log.error, "Failed to load video asset")
                            continuation.resume(throwing: NSError(domain: "", code: -1,
                                                               userInfo: [NSLocalizedDescriptionKey: "Failed to load video asset"]))
                        }
                    }
                }
                
                guard let urlAsset = avAsset as? AVURLAsset else {
                    Log.p(Log.video, Log.read, Log.error, "Could not get URL from asset")
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get URL from asset"])
                }
                
                // Create a temporary copy in our sandbox
                Log.p(Log.video, Log.save, "Creating temporary copy of video")
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try FileManager.default.copyItem(at: urlAsset.url, to: tempURL)
                Log.p(Log.video, Log.save, Log.success, "Created temporary copy at: \(tempURL.path)")
                
                await MainActor.run {
                    self.selectedVideo = tempURL
                }
            } catch {
                Log.p(Log.video, Log.read, Log.error, "Failed to load video: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                }
            }
        }
    }
    
    func uploadVideo(userId: String, username: String) {
        Log.p(Log.video, Log.event, "Starting upload process")
        Log.p(Log.video, Log.event, "Selected video URL: \(String(describing: selectedVideo))")
        
        guard let videoURL = selectedVideo else {
            Log.p(Log.video, Log.event, Log.error, "No video URL available")
            errorMessage = "No video selected"
            showingError = true
            return
        }
        Log.p(Log.video, Log.event, "Video exists at: \(videoURL.path)")
        
        guard !effectiveTitle.isEmpty else {
            Log.p(Log.video, Log.event, Log.error, "No title provided")
            errorMessage = "Title is required"
            showingError = true
            return
        }
        Log.p(Log.video, Log.event, "Title: \(effectiveTitle)")
        
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
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                Log.p(Log.video, Log.event, "Upload publisher completed")
                self.isUploading = false
                self.publishState = ""
            },
            receiveValue: { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case .creatingDocument:
                    Log.p(Log.video, Log.event, "Creating document")
                    self.publishState = "Creating document..."
                    
                case let .uploading(progress):
                    Log.p(Log.video, Log.event, "Upload progress: \(Int(progress * 100))%")
                    self.uploadProgress = progress
                    self.publishState = "Uploading video: \(Int(progress * 100))%"
                    
                case .updatingDocument:
                    Log.p(Log.video, Log.event, "Updating document")
                    self.publishState = "Finalizing..."
                    
                case .completed:
                    Log.p(Log.video, Log.event, Log.success, "Upload completed successfully")
                    self.isUploading = false
                    self.showingSuccess = true
                    self.publishState = ""
                    
                case let .error(error):
                    Log.p(Log.video, Log.event, Log.error, "Upload failed: \(error.localizedDescription)")
                    self.isUploading = false
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.publishState = ""
                }
            }
        )
        .store(in: &cancellables)
    }
    
    func updateAuthService(_ newService: AuthenticationService) {
        Log.p(Log.video, Log.update, "Updating auth service")
        authService = newService
    }
    
    func cancelUpload() {
        Log.p(Log.video, Log.event, "User cancelled upload")
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