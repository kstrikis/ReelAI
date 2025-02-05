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
    var errorMessage: String?

    private let cameraManager = CameraManager.shared
    private let localVideoService = LocalVideoService.shared
    private let authService: AuthenticationService
    private var recordingURL: URL?

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
                                Circle()
                                    .fill(viewModel?.isRecording == true ? Color.red : Color.white)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 4)
                                            .frame(width: 70, height: 70)
                                    )
                            })

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
