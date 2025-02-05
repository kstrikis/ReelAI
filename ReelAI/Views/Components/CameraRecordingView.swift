import AVFoundation
import Combine
import SwiftUI

// MARK: - Publisher Extension

extension Publisher {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            print("🔄 Converting publisher to async...")
            var cancellable: AnyCancellable?

            cancellable = self.sink(
                receiveCompletion: { completion in
                    print("🔄 Publisher completed")
                    switch completion {
                    case .finished:
                        break
                    case let .failure(error):
                        print("🔄 Publisher failed: \(error)")
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    print("🔄 Publisher received value")
                    continuation.resume(returning: value)
                    cancellable?.cancel()
                }
            )

            print("🔄 Publisher subscription created")
        }
    }
}

// MARK: - Camera Errors

enum CameraError: LocalizedError {
    case deviceNotAvailable
    case setupFailed(Error)
    case outputNotAvailable
    case recordingFailed(Error)
    case uploadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .deviceNotAvailable: "Failed to get video device"
        case let .setupFailed(error): "Failed to setup camera session: \(error.localizedDescription)"
        case .outputNotAvailable: "Video output not available"
        case let .recordingFailed(error): "Recording failed: \(error.localizedDescription)"
        case let .uploadFailed(error): "Upload failed: \(error.localizedDescription)"
        }
    }
}

@Observable
final class CameraViewModel {
    var currentFrame: CGImage?
    var isRecording = false
    var isUploading = false
    var errorMessage: String?

    private let cameraManager = CameraManager.shared
    private let uploadService = VideoUploadService.shared
    private let videoService = VideoService.shared
    private let localVideoService = LocalVideoService.shared
    private let authService: AuthenticationService
    private var recordingURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init(authService: AuthenticationService) {
        AppLogger.methodEntry(AppLogger.ui)
        self.authService = authService
        AppLogger.methodExit(AppLogger.ui)
    }

    func handleCameraPreviews() async {
        AppLogger.methodEntry(AppLogger.ui)
        await cameraManager.prepareAndStart()
        for await image in cameraManager.previewStream {
            Task { @MainActor in
                currentFrame = image
            }
        }
        AppLogger.methodExit(AppLogger.ui)
    }

    func stopCamera() {
        print("📸 🛑 Stopping camera session")
        cameraManager.stopSession()
        print("📸 ✅ Camera session stopped")
    }

    func toggleRecording() async {
        print("📸 🎬 Toggle recording called, current state: \(isRecording)")

        do {
            if isRecording {
                print("📸 ⏹️ Stopping recording...")
                // Stop recording
                let tempURL = try await cameraManager.stopRecording()
                isRecording = false
                print("📸 💾 Recording stopped, file at: \(tempURL.path)")

                // Save to local storage
                print("📸 📝 Saving to local storage...")
                let persistentURL = try await localVideoService.saveVideo(from: tempURL).async()
                print("📸 ✅ Video saved to: \(persistentURL.path)")
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                print("📸 🧹 Cleaned up temporary file")
                
            } else {
                print("📸 ▶️ Starting recording...")
                // Start recording
                recordingURL = try await cameraManager.startRecording()
                isRecording = true
                print("📸 📹 Recording started, will save to: \(recordingURL?.path ?? "nil")")
            }
            errorMessage = nil
        } catch {
            print("❌ 💥 Recording error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            AppLogger.error(AppLogger.ui, error)
        }
    }

    private func uploadVideo() async {
        print("📸 📤 Starting video upload process")

        guard let tempURL = recordingURL else {
            print("❌ 🚫 Upload failed: No video URL available")
            errorMessage = "No video to upload"
            return
        }
        print("📸 📁 Temporary video file location: \(tempURL.path)")

        isUploading = true
        print("📸 ⚙️ Upload state set to true")

        // First check Firebase auth state
        guard let userId = authService.currentUser?.uid else {
            print("❌ 🔒 Upload failed: No Firebase user found")
            print("📸 🔑 Auth state: \(String(describing: authService.currentUser))")
            errorMessage = "Not signed in"
            isUploading = false
            return
        }

        // Save to persistent storage first
        print("�� 📝 Saving video to persistent storage...")
        do {
            let persistentURL = try await localVideoService.saveVideo(from: tempURL).async()
            print("📸 ✅ Video saved to persistent storage at: \(persistentURL.path)")
            
            // Clean up the temporary file
            try FileManager.default.removeItem(at: tempURL)
            print("📸 🧹 Cleaned up temporary file")
            recordingURL = persistentURL
        } catch {
            print("❌ 💥 Failed to save video to persistent storage: \(error.localizedDescription)")
            errorMessage = "Failed to save video"
            isUploading = false
            return
        }

        // Then check user profile separately with retry logic
        if authService.userProfile == nil {
            print("📸 📤 User profile not loaded, attempting to load...")
            print("📸 📤 Waiting for profile to load (max 5 seconds)...")

            // Wait for up to 5 seconds for the profile to load
            for _ in 0 ..< 10 {
                if authService.userProfile != nil { break }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                print("📸 📤 Still waiting for profile...")
            }
        }

        guard let username = authService.userProfile?.username else {
            print("❌ 🔒 Upload failed: Could not load user profile")
            print("📸 🔑 Firebase UID: \(userId)")
            print("📸 🔑 Profile state: \(String(describing: authService.userProfile))")
            print("📸 🔑 Please try again or check your connection")
            errorMessage = "Could not load profile. Please try again."
            isUploading = false
            return
        }

        print("📸 📤 Starting upload with userId: \(userId)")
        print("📸 📤 Username: \(username)")
        print("📸 📤 Auth details:")
        print("  - Firebase UID: \(userId)")
        print("  - Username: \(username)")
        print("  - Email: \(authService.userProfile?.email ?? "none")")

        uploadService.uploadVideo(at: recordingURL!, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else {
                    print("⚠️ 🔒 Self reference lost during upload")
                    return
                }

                switch state {
                case let .progress(progress):
                    print("�� 🎥 Upload progress update received: \(String(format: "%.1f", progress * 100))%")

                case let .completed(ref):
                    print("🎥 🎥 Upload completed successfully")
                    print("🎥 🎥 Storage reference: \(ref.fullPath)")
                    print("🎥 🎥 Creating Firestore metadata...")

                    // Create Firestore metadata
                    Task {
                        do {
                            print("🎥 🎥 Calling VideoService.createVideo...")
                            let video = try await self.videoService.createVideo(
                                userId: userId,
                                username: username,
                                rawVideoURL: ref.fullPath
                            ).async()

                            print("🎥 🎥 Video metadata created successfully")
                            print("🎥 🎥 Video ID: \(video.id ?? "unknown")")
                            print("🎥 🎥 Raw video URL: \(video.rawVideoURL)")

                            self.isUploading = false
                            print("✅ 🎥 Upload process completed successfully")

                        } catch {
                            print("❌ 💥 Metadata creation failed: \(error.localizedDescription)")
                            print("❌ 💥 Error details: \(error)")
                            self.errorMessage = error.localizedDescription
                            self.isUploading = false
                            AppLogger.error(AppLogger.ui, error)
                        }
                    }

                case let .failure(error):
                    print("❌ 💥 Upload failed in CameraViewModel")
                    print("❌ 💥 Error: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("❌ 💥 Error domain: \(nsError.domain)")
                        print("❌ 💥 Error code: \(nsError.code)")
                        print("❌ 💥 User info: \(nsError.userInfo)")
                    }
                    errorMessage = error.localizedDescription
                    isUploading = false
                    AppLogger.error(AppLogger.ui, CameraError.uploadFailed(error))
                }
            }
            .store(in: &cancellables)

        print("📸 📊 Upload publisher subscription created")
        AppLogger.methodExit(AppLogger.ui)
    }
}

struct CameraRecordingView: View {
    let isActive: Bool
    @EnvironmentObject private var authService: AuthenticationService
    @State private var viewModel: CameraViewModel?
    @State private var showingGallery = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                if let image = viewModel?.currentFrame {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    ContentUnavailableView("No camera feed", systemImage: "video.slash")
                }

                // Controls overlay
                VStack {
                    // Top controls
                    HStack {
                        Button(action: {
                            showingGallery = true
                        }, label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        })
                        
                        Spacer()
                        
                        Button(action: {
                            Task {
                                await CameraManager.shared.switchCamera()
                            }
                        }, label: {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        })
                    }
                    .padding(.top, 10)

                    Spacer()

                    // Bottom controls
                    VStack(spacing: 20) {
                        if let error = viewModel?.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }

                        HStack {
                            Spacer()

                            // Record button
                            Button(action: {
                                Task {
                                    await viewModel?.toggleRecording()
                                }
                            }, label: {
                                if viewModel?.isUploading == true {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: 80, height: 80)
                                } else {
                                    Circle()
                                        .fill(viewModel?.isRecording == true ? Color.red : Color.white)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                                .frame(width: 70, height: 70)
                                        )
                                }
                            })
                            .disabled(viewModel?.isUploading == true)

                            Spacer()
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingGallery, onDismiss: {
            // Restart camera when returning from gallery
            if isActive {
                Task {
                    await viewModel?.handleCameraPreviews()
                }
            }
        }) {
            NavigationView {
                GalleryView(authService: authService)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingGallery = false
                            }
                        }
                    }
            }
            .onAppear {
                // Stop camera when showing gallery
                viewModel?.stopCamera()
            }
        }
        .onChange(of: isActive) { _, isNowActive in
            if isNowActive {
                // Initialize viewModel with authService
                viewModel = CameraViewModel(authService: authService)
                // Start camera when swiping to this view
                Task {
                    await viewModel?.handleCameraPreviews()
                }
            } else {
                // Stop camera when swiping away
                viewModel?.stopCamera()
            }
        }
    }
}

#if DEBUG
    struct CameraRecordingView_Previews: PreviewProvider {
        static var previews: some View {
            CameraRecordingView(isActive: true)
        }
    }
#endif
