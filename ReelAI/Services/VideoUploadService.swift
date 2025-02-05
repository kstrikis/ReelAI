import Combine
import FirebaseStorage
import FirebaseAuth
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
        AppLogger.methodEntry(AppLogger.ui)
        print("📤 VideoUploadService singleton initialized")
        
        // Initialize Firebase Storage
        storage = Storage.storage()
        
        // Get the default bucket from Firebase configuration
        if let bucket = storage.app.options.storageBucket, !bucket.isEmpty {
            print("📤 Using Firebase Storage bucket: \(bucket)")
            print("📤 Storage app name: \(storage.app.name)")
        } else {
            print("⚠️ No storage bucket configured in GoogleService-Info.plist")
            print("⚠️ Firebase app name: \(storage.app.name)")
            print("⚠️ Firebase app options: \(storage.app.options)")
        }
        
        AppLogger.methodExit(AppLogger.ui)
    }
    
    private func verifyFileSize(at url: URL, retryCount: Int = 0, maxRetries: Int = 3) -> AnyPublisher<Int64, Error> {
        print("📤 Verifying file size (attempt \(retryCount + 1) of \(maxRetries + 1))...")
        
        return Future<Int64, Error> { promise in
            // Calculate delay with exponential backoff
            let delay = retryCount == 0 ? 1.0 : min(pow(2.0, Double(retryCount)) * 0.5, 4.0)
            print("📤 Waiting \(String(format: "%.1f", delay)) seconds for file to stabilize...")
            
            // First size check
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize1 = attributes[.size] as? Int64 ?? 0
                print("📤 Initial file size: \(String(format: "%.2f", Double(fileSize1) / 1_000_000.0))MB")
                
                // Wait and check again
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        let fileSize2 = attributes[.size] as? Int64 ?? 0
                        print("📤 Second file size check: \(String(format: "%.2f", Double(fileSize2) / 1_000_000.0))MB")
                        
                        if fileSize1 == fileSize2 {
                            guard fileSize1 > 0 else {
                                promise(.failure(NSError(domain: "", code: -1, 
                                    userInfo: [NSLocalizedDescriptionKey: "Video file is empty"])))
                                return
                            }
                            print("✅ File size is stable at \(String(format: "%.2f", Double(fileSize1) / 1_000_000.0))MB")
                            promise(.success(fileSize1))
                        } else {
                            print("⚠️ File size is unstable. First: \(fileSize1), Second: \(fileSize2)")
                            if retryCount < maxRetries {
                                print("📤 Retrying size verification...")
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
                                promise(.failure(NSError(domain: "", code: -1, 
                                    userInfo: [NSLocalizedDescriptionKey: "File size remained unstable after \(maxRetries + 1) attempts"])))
                            }
                        }
                    } catch {
                        promise(.failure(error))
                    }
                }
            } catch {
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func uploadVideo(at url: URL, userId: String) -> AnyPublisher<VideoUploadState, Never> {
        AppLogger.methodEntry(AppLogger.ui)
        print("📤 Starting video upload from: \(url.path)")
        print("📤 User ID from parameter: \(userId)")
        
        // Check auth state immediately
        if let currentUser = Auth.auth().currentUser {
            print("📤 Current Firebase user exists:")
            print("  - UID: \(currentUser.uid)")
            print("  - Is Anonymous: \(currentUser.isAnonymous)")
            print("  - Email: \(currentUser.email ?? "none")")
            
            // Verify userId matches current user
            if currentUser.uid != userId {
                print("⚠️ Warning: Provided userId (\(userId)) doesn't match current user (\(currentUser.uid))")
            }
        } else {
            print("⚠️ No current Firebase user found in Auth.auth().currentUser")
        }
        
        return Future<VideoUploadState, Never> { promise in
            print("📤 Initializing upload Future...")
            
            // Double check auth state again inside Future
            guard let currentUser = Auth.auth().currentUser else {
                print("❌ Upload failed: No authenticated user found")
                print("📤 Auth state details:")
                print("  - Auth.auth().currentUser: \(String(describing: Auth.auth().currentUser))")
                let error = NSError(domain: "VideoUploadService", 
                    code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "No authenticated user found"])
                promise(.success(.failure(error)))
                return
            }
            
            print("✅ User authenticated:")
            print("  - Current user ID: \(currentUser.uid)")
            print("  - Matches provided ID: \(currentUser.uid == userId)")
            
            // First verify the file exists
            print("📤 Checking if file exists at: \(url.path)")
            guard FileManager.default.fileExists(atPath: url.path) else {
                let error = NSError(domain: "", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Video file not found at path: \(url.path)"])
                print("❌ Upload failed: Video file not found")
                promise(.success(.failure(error)))
                return
            }
            print("✅ File exists")
            
            // Verify file size with retries
            self.verifyFileSize(at: url)
                .sink(
                    receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            print("❌ File size verification failed: \(error.localizedDescription)")
                            promise(.success(.failure(error)))
                        }
                    },
                    receiveValue: { fileSize in
                        // Create storage reference with fresh reference
                        print("📤 Creating storage reference...")
                        let filename = UUID().uuidString + ".mp4"
                        let videoRef = self.storage.reference().child("videos/\(userId)/raw/\(filename)")
                        print("📤 Upload destination: \(videoRef.bucket)/\(videoRef.fullPath)")
                        print("✅ Storage reference created")
                        
                        // Create metadata
                        print("📤 Creating metadata...")
                        let metadata = StorageMetadata()
                        metadata.contentType = "video/mp4"
                        metadata.customMetadata = ["fileSize": "\(fileSize)"]
                        print("✅ Metadata created")
                        
                        // Create upload task
                        print("📤 Creating upload task...")
                        let uploadTask = videoRef.putFile(from: url, metadata: metadata)
                        print("✅ Upload task created")
                        
                        // Monitor upload progress
                        print("📤 Setting up progress monitoring...")
                        uploadTask.observe(.progress) { snapshot in
                            if let progress = snapshot.progress {
                                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                                let bytesTransferred = Double(progress.completedUnitCount) / 1_000_000.0 // MB
                                let totalBytes = Double(progress.totalUnitCount) / 1_000_000.0 // MB
                                print("📤 Upload progress: \(String(format: "%.1f", percentComplete * 100))%")
                                print("📤 Bytes transferred: \(String(format: "%.2f", bytesTransferred))MB / \(String(format: "%.2f", totalBytes))MB")
                                print("📤 Current speed: \(String(format: "%.2f", progress.throughput ?? 0 / 1_000_000.0))MB/s")
                                promise(.success(.progress(percentComplete)))
                            } else {
                                print("⚠️ Progress snapshot missing progress information")
                            }
                        }
                        print("✅ Progress monitoring set up")
                        
                        // Handle upload completion
                        print("📤 Setting up completion handler...")
                        uploadTask.observe(.success) { _ in
                            print("📤 Upload completed successfully")
                            print("📤 Final storage path: \(videoRef.fullPath)")
                            print("📤 Full URL: gs://\(videoRef.bucket)/\(videoRef.fullPath)")
                            promise(.success(.completed(videoRef)))
                        }
                        print("✅ Completion handler set up")
                        
                        // Handle upload failure with detailed error handling
                        print("📤 Setting up failure handler...")
                        uploadTask.observe(.failure) { snapshot in
                            if let error = snapshot.error as NSError? {
                                print("❌ Upload failed: \(error.localizedDescription)")
                                print("❌ Error details:")
                                print("  - Domain: \(error.domain)")
                                print("  - Code: \(error.code)")
                                print("  - Description: \(error.localizedDescription)")
                                print("  - User Info: \(error.userInfo)")
                                
                                if error.domain == StorageErrorDomain {
                                    switch StorageErrorCode(rawValue: error.code) {
                                    case .unauthorized:
                                        print("❌ Storage Error: Unauthorized. Check Firebase Storage Rules")
                                        print("📤 Current user ID: \(userId)")
                                        print("📤 Attempted path: \(videoRef.fullPath)")
                                        print("📤 Full attempted URL: gs://\(videoRef.bucket)/\(videoRef.fullPath)")
                                    case .quotaExceeded:
                                        print("❌ Storage Error: Quota exceeded")
                                        print("📤 Check your Firebase Storage quota limits")
                                    case .unauthenticated:
                                        print("❌ Storage Error: User is not authenticated")
                                        print("📤 Auth state needs to be verified")
                                    case .retryLimitExceeded:
                                        print("❌ Storage Error: Retry limit exceeded")
                                        print("📤 Network conditions may be poor")
                                    case .nonMatchingChecksum:
                                        print("❌ Storage Error: Upload corrupted or interrupted")
                                        print("📤 File integrity check failed")
                                    case .downloadSizeExceeded:
                                        print("❌ Storage Error: File too large")
                                        print("📤 Check your Firebase Storage file size limits")
                                    case .cancelled:
                                        print("❌ Storage Error: Upload cancelled")
                                        print("📤 Upload was manually cancelled or interrupted")
                                    case .unknown:
                                        print("❌ Storage Error: Unknown error")
                                        print("📤 Check Firebase Console for more details")
                                    default:
                                        print("❌ Storage Error: \(error.localizedDescription)")
                                        print("❌ Error domain: \(error.domain), code: \(error.code)")
                                    }
                                }
                                promise(.success(.failure(error)))
                            } else {
                                print("⚠️ Upload failed but no error information available")
                                let unknownError = NSError(domain: "", code: -1, 
                                    userInfo: [NSLocalizedDescriptionKey: "Unknown upload error"])
                                promise(.success(.failure(unknownError)))
                            }
                        }
                        print("✅ Failure handler set up")
                        print("📤 Upload task ready to begin...")
                    }
                )
                .store(in: &self.cancellables)
        }
        .handleEvents(receiveSubscription: { _ in
            print("📤 Upload publisher received subscription")
            print("📤 Upload process beginning...")
        }, receiveOutput: { state in
            switch state {
            case .progress(let progress):
                print("📤 Publisher received progress update: \(String(format: "%.1f", progress * 100))%")
            case .completed(let ref):
                print("📤 Publisher received completion notification")
                print("📤 Final reference path: \(ref.fullPath)")
            case .failure(let error):
                print("📤 Publisher received error: \(error.localizedDescription)")
            }
        }, receiveCompletion: { completion in
            print("📤 Upload publisher completed")
            switch completion {
            case .finished:
                print("📤 Publisher finished normally")
            case .failure(let error):
                print("📤 Publisher failed: \(error.localizedDescription)")
            }
        }, receiveCancel: {
            print("📤 Upload publisher cancelled")
        })
        .share() // Share the publisher to allow multiple subscribers
        .eraseToAnyPublisher()
    }
} 