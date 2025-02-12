import Combine
import FirebaseAuth
import FirebaseStorage
import Foundation

enum VideoUploadState {
    case progress(Double)
    case completed(StorageReference)
    case failure(Error)
}

final class VideoUploadService {
    static let shared = VideoUploadService()
    private let storage: Storage
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Log.p(Log.upload, Log.start, "Initializing VideoUploadService")

        // Initialize Firebase Storage
        storage = Storage.storage()

        // Get the default bucket from Firebase configuration
        if let bucket = storage.app.options.storageBucket, !bucket.isEmpty {
            Log.p(Log.storage, Log.event, "Using Firebase Storage bucket: \(bucket)")
            Log.p(Log.storage, Log.event, "Storage app name: \(storage.app.name)")
        } else {
            Log.p(Log.storage, Log.event, Log.warning, "No storage bucket configured in GoogleService-Info.plist")
            Log.p(Log.storage, Log.event, Log.warning, "Firebase app name: \(storage.app.name)")
            Log.p(Log.storage, Log.event, Log.warning, "Firebase app options: \(storage.app.options)")
        }

        Log.p(Log.upload, Log.exit, "VideoUploadService initialization complete")
    }

    private func verifyFileSize(at url: URL, retryCount: Int = 0, maxRetries: Int = 3) -> AnyPublisher<Int64, Error> {
        Log.p(Log.upload, Log.event, "Verifying file size (attempt \(retryCount + 1) of \(maxRetries + 1))")

        return Future<Int64, Error> { promise in
            // Calculate delay with exponential backoff
            let delay = retryCount == 0 ? 1.0 : min(pow(2.0, Double(retryCount)) * 0.5, 4.0)
            Log.p(Log.upload, Log.event, "Waiting \(String(format: "%.1f", delay)) seconds for file to stabilize")

            // First size check
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize1 = attributes[.size] as? Int64 ?? 0
                Log.p(Log.upload, Log.event, "Initial file size: \(String(format: "%.2f", Double(fileSize1) / 1_000_000.0))MB")

                // Wait and check again
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        let fileSize2 = attributes[.size] as? Int64 ?? 0
                        Log.p(Log.upload, Log.event, "Second file size check: \(String(format: "%.2f", Double(fileSize2) / 1_000_000.0))MB")

                        if fileSize1 == fileSize2 {
                            guard fileSize1 > 0 else {
                                Log.p(Log.upload, Log.event, Log.error, "Video file is empty")
                                promise(.failure(NSError(domain: "", code: -1,
                                                         userInfo: [NSLocalizedDescriptionKey: "Video file is empty"])))
                                return
                            }
                            Log.p(Log.upload, Log.event, Log.success, "File size is stable at \(String(format: "%.2f", Double(fileSize1) / 1_000_000.0))MB")
                            promise(.success(fileSize1))
                        } else {
                            Log.p(Log.upload, Log.event, Log.warning, "File size is unstable. First: \(fileSize1), Second: \(fileSize2)")
                            if retryCount < maxRetries {
                                Log.p(Log.upload, Log.event, "Retrying size verification")
                                self.verifyFileSize(at: url, retryCount: retryCount + 1, maxRetries: maxRetries)
                                    .sink(
                                        receiveCompletion: { completion in
                                            if case let .failure(error) = completion {
                                                promise(.failure(error))
                                            }
                                        },
                                        receiveValue: { size in
                                            promise(.success(size))
                                        }
                                    )
                                    .store(in: &self.cancellables)
                            } else {
                                Log.p(Log.upload, Log.event, Log.error, "File size remained unstable after \(maxRetries + 1) attempts")
                                promise(.failure(NSError(domain: "", code: -1,
                                                         userInfo: [NSLocalizedDescriptionKey: "File size remained unstable after \(maxRetries + 1) attempts"])))
                            }
                        }
                    } catch {
                        Log.p(Log.upload, Log.event, Log.error, "Failed to check file size: \(error.localizedDescription)")
                        promise(.failure(error))
                    }
                }
            } catch {
                Log.p(Log.upload, Log.event, Log.error, "Failed to check initial file size: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }

    func uploadVideo(at url: URL, userId: String, videoId: String) -> AnyPublisher<VideoUploadState, Never> {
        Log.p(Log.upload, Log.start, "Starting video upload from: \(url.path)")
        Log.p(Log.upload, Log.event, "User ID: \(userId)")
        Log.p(Log.upload, Log.event, "Video ID: \(videoId)")
        
        let subject = PassthroughSubject<VideoUploadState, Never>()
        
        Task {
            // Check auth state
            guard let currentUser = Auth.auth().currentUser else {
                Log.p(Log.auth, Log.event, Log.error, "No authenticated user found")
                subject.send(.failure(NSError(domain: "VideoUploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user found"])))
                subject.send(completion: .finished)
                return
            }
            Log.p(Log.auth, Log.event, Log.success, "User authenticated - ID: \(currentUser.uid)")
            
            Log.p(Log.upload, Log.event, "Checking if file exists at: \(url.path)")
            guard FileManager.default.fileExists(atPath: url.path) else {
                Log.p(Log.upload, Log.event, Log.error, "Video file not found at path: \(url.path)")
                subject.send(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file not found at path: \(url.path)"])))
                subject.send(completion: .finished)
                return
            }
            Log.p(Log.upload, Log.event, Log.success, "File exists")
            
            // Verify file size with retries
            self.verifyFileSize(at: url)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        Log.p(Log.upload, Log.event, Log.error, "File size verification failed: \(error.localizedDescription)")
                        subject.send(.failure(error))
                        subject.send(completion: .finished)
                    }
                }, receiveValue: { fileSize in
                    Log.p(Log.upload, Log.event, "Creating storage reference")
                    let videoRef = self.storage.reference().child("videos/\(userId)/\(videoId).mp4")
                    Log.p(Log.storage, Log.event, "Upload destination: \(videoRef.bucket)/\(videoRef.fullPath)")
                    
                    Log.p(Log.storage, Log.event, "Creating metadata")
                    let metadata = StorageMetadata()
                    metadata.contentType = "video/mp4"
                    metadata.customMetadata = ["fileSize": "\(fileSize)"]
                    // Set Cache-Control header for 1 hour caching
                    metadata.cacheControl = "public, max-age=3600"
                    
                    Log.p(Log.upload, Log.uploadAction, "Creating upload task")
                    let uploadTask = videoRef.putFile(from: url, metadata: metadata)
                    
                    // Observe progress
                    uploadTask.observe(.progress) { snapshot in
                        if let progress = snapshot.progress {
                            let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                            Log.p(Log.upload, Log.uploadAction, "Progress: \(String(format: "%.1f", percentComplete * 100))%")
                            subject.send(.progress(percentComplete))
                        } else {
                            Log.p(Log.upload, Log.event, Log.warning, "Progress snapshot missing progress information")
                        }
                    }
                    
                    // Handle upload completion
                    uploadTask.observe(.success) { _ in
                        Log.p(Log.upload, Log.uploadAction, Log.success, "Upload completed successfully")
                        Log.p(Log.storage, Log.event, "Final storage path: \(videoRef.fullPath)")
                        subject.send(.completed(videoRef))
                        subject.send(completion: .finished)
                    }
                    
                    // Handle upload failure
                    uploadTask.observe(.failure) { snapshot in
                        if let error = snapshot.error as NSError? {
                            Log.p(Log.upload, Log.uploadAction, Log.error, "Upload failed: \(error.localizedDescription)")
                            subject.send(.failure(error))
                            subject.send(completion: .finished)
                        } else {
                            Log.p(Log.upload, Log.event, Log.error, "Upload failed but no error information available")
                            let unknownError = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown upload error"])
                            subject.send(.failure(unknownError))
                            subject.send(completion: .finished)
                        }
                    }
                    Log.p(Log.upload, Log.uploadAction, "Upload task ready to begin")
                })
                .store(in: &self.cancellables)
        }
        
        return subject.eraseToAnyPublisher()
    }
}
