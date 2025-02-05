import SwiftUI
import PhotosUI
import Combine
import AVKit
import FirebaseAuth

struct PublishingView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PublishingViewModel()
    
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
                    CustomTextField(placeholder: "Title", text: $viewModel.title)
                    
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
                            ProgressView("Uploading... \(Int(viewModel.uploadProgress * 100))%")
                                .tint(.white)
                            
                            Button("Cancel", role: .destructive) {
                                viewModel.cancelUpload()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    } else {
                        Button(action: viewModel.uploadVideo) {
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
    
    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .onDisappear {
                // Stop playback when view disappears
                AVPlayer(url: url).pause()
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
    
    private var uploadCancellable: AnyCancellable?
    
    var canUpload: Bool {
        !title.isEmpty && selectedVideo != nil
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
    
    func uploadVideo() {
        guard let videoURL = selectedVideo,
              let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Missing video or user ID"
            showingError = true
            return
        }
        
        isUploading = true
        
        uploadCancellable = VideoUploadService.shared.uploadVideo(at: videoURL, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case let .progress(progress):
                    self.uploadProgress = progress
                case .completed:
                    self.isUploading = false
                    self.showingSuccess = true
                case let .failure(error):
                    self.isUploading = false
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                }
            }
    }
    
    func cancelUpload() {
        uploadCancellable?.cancel()
        isUploading = false
        uploadProgress = 0
    }
}

#Preview {
    NavigationView {
        PublishingView()
            .environmentObject(AuthenticationService.preview)
    }
} 