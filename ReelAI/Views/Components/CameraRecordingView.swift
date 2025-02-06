import AVFoundation
import Combine
import SwiftUI

// MARK: - Publisher Extension

extension Publisher {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            Log.p(Log.app, Log.start, "Converting publisher to async")
            var cancellable: AnyCancellable?

            cancellable = self.sink(
                receiveCompletion: { completion in
                    Log.p(Log.app, Log.event, "Publisher completed")
                    switch completion {
                    case .finished:
                        break
                    case let .failure(error):
                        Log.p(Log.app, Log.event, Log.error, "Publisher failed: \(error)")
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    Log.p(Log.app, Log.event, "Publisher received value")
                    continuation.resume(returning: value)
                    cancellable?.cancel()
                }
            )

            Log.p(Log.app, Log.event, "Publisher subscription created")
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
        Log.p(Log.camera, Log.start, "Initializing CameraViewModel")
        self.authService = authService
        Log.p(Log.camera, Log.exit, "CameraViewModel initialized")
    }

    func handleCameraPreviews() async {
        Log.p(Log.camera, Log.start, "Starting camera preview stream")
        await cameraManager.prepareAndStart()
        for await image in cameraManager.previewStream {
            Task { @MainActor in
                currentFrame = image
            }
        }
        Log.p(Log.camera, Log.exit, "Camera preview stream ended")
    }

    func stopCamera() {
        Log.p(Log.camera, Log.stop, "Stopping camera session")
        cameraManager.stopSession()
        Log.p(Log.camera, Log.event, Log.success, "Camera session stopped")
    }

    func toggleRecording() async {
        Log.p(Log.camera, Log.event, "Toggle recording called, current state: \(isRecording)")

        do {
            if isRecording {
                Log.p(Log.camera, Log.stop, "Stopping recording")
                // Stop recording
                let tempURL = try await cameraManager.stopRecording()
                isRecording = false
                Log.p(Log.camera, Log.event, "Recording stopped, file at: \(tempURL.path)")

                // Save to local storage
                Log.p(Log.storage, Log.save, "Saving to local storage")
                let persistentURL = try await localVideoService.saveVideo(from: tempURL).async()
                Log.p(Log.storage, Log.save, Log.success, "Video saved to: \(persistentURL.path)")

                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                Log.p(Log.storage, Log.delete, "Cleaned up temporary file")

            } else {
                Log.p(Log.camera, Log.start, "Starting recording")
                // Start recording
                recordingURL = try await cameraManager.startRecording()
                isRecording = true
                Log.p(Log.camera, Log.event, Log.success, "Recording started, will save to: \(recordingURL?.path ?? "nil")")
            }
            errorMessage = nil
        } catch {
            Log.p(Log.camera, Log.event, Log.error, "Recording error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
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
                            Log.p(Log.camera, Log.event, "User tapped to open gallery")
                            showingGallery = true
                        }, label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        })

                        Spacer()

                        Button(action: {
                            Log.p(Log.camera, Log.event, "User tapped to switch camera")
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
                                Log.p(Log.camera, Log.event, "User tapped record button")
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
                Log.p(Log.camera, Log.start, "Restarting camera after gallery dismissal")
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
                                Log.p(Log.camera, Log.event, "User dismissed gallery")
                                showingGallery = false
                            }
                        }
                    }
            }
            .onAppear {
                // Stop camera when showing gallery
                Log.p(Log.camera, Log.stop, "Stopping camera for gallery view")
                viewModel?.stopCamera()
            }
        }
        .onChange(of: isActive) { _, isNowActive in
            if isNowActive {
                Log.p(Log.camera, Log.start, "Camera view became active")
                // Initialize viewModel with authService
                viewModel = CameraViewModel(authService: authService)
                // Start camera when swiping to this view
                Task {
                    await viewModel?.handleCameraPreviews()
                }
            } else {
                Log.p(Log.camera, Log.stop, "Camera view became inactive")
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
