import AVFoundation
import Combine
import Foundation
import Photos
import UIKit

class LocalVideoService {
    static let shared = LocalVideoService()

    private init() {
        Log.p(Log.storage, Log.start, "Initializing LocalVideoService")
        Log.p(Log.storage, Log.exit, "LocalVideoService initialized")
    }

    func saveVideo(from tempURL: URL) -> AnyPublisher<URL, Error> {
        Log.p(Log.storage, Log.save, "Starting video save operation")

        return Future<URL, Error> { promise in
            // Verify the temp file exists and is readable
            guard FileManager.default.fileExists(atPath: tempURL.path) else {
                Log.p(Log.storage, Log.read, Log.error, "Temp file not accessible: \(tempURL.path)")
                promise(.failure(NSError(domain: "LocalVideoService", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "Video file not accessible"])))
                return
            }

            // Function to attempt save with retry
            func attemptSave(retryCount: Int = 0, maxRetries: Int = 3) {
                Log.p(Log.storage, Log.save, "Attempting to save video (attempt \(retryCount + 1)/\(maxRetries + 1))")

                Task {
                    do {
                        // First verify we can read the file
                        let videoData = try Data(contentsOf: tempURL, options: .alwaysMapped)
                        Log.p(Log.storage, Log.read, "Video file size: \(Double(videoData.count) / 1_000_000.0)MB")

                        try await PHPhotoLibrary.shared().performChanges {
                            Log.p(Log.storage, Log.save, "Creating Photos asset")
                            let request = PHAssetCreationRequest.forAsset()
                            request.addResource(with: .video, fileURL: tempURL, options: nil)
                        }
                        Log.p(Log.storage, Log.save, Log.success, "Video saved to Photos")
                        promise(.success(tempURL))
                    } catch {
                        Log.p(Log.storage, Log.save, Log.error, "Save attempt \(retryCount + 1) failed: \(error.localizedDescription)")
                        if let phError = error as? PHPhotosError {
                            Log.p(Log.storage, Log.save, Log.error, "Photos error code: \(phError.errorCode)")
                        }

                        // If we haven't maxed out retries, wait and try again
                        if retryCount < maxRetries {
                            Log.p(Log.storage, Log.event, "Waiting before retry")
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                            attemptSave(retryCount: retryCount + 1, maxRetries: maxRetries)
                        } else {
                            promise(.failure(error))
                        }
                    }
                }
            }

            // Start first attempt after a short delay
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second initial delay
                attemptSave()
            }
        }
        .eraseToAnyPublisher()
    }

    func getAllVideos() -> [URL] {
        Log.p(Log.storage, Log.read, "Fetching videos from Photos")

        // First check Photos permission status
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        Log.p(Log.storage, Log.event, "Photos permission status: \(status.rawValue)")

        // If not authorized, handle permission request
        if status != .authorized {
            Log.p(Log.storage, Log.event, Log.warning, "Photos access not authorized (status: \(status.rawValue))")

            // Only request permission if not determined yet
            if status == .notDetermined {
                Log.p(Log.storage, Log.event, "Requesting Photos permission")
                let semaphore = DispatchSemaphore(value: 0)
                var granted = false

                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    granted = newStatus == .authorized
                    semaphore.signal()
                }
                semaphore.wait()

                if !granted {
                    Log.p(Log.storage, Log.event, Log.error, "Photos permission denied")
                    return []
                }
            } else {
                Log.p(Log.storage, Log.event, Log.error, "Photos permission not available")
                return []
            }
        }

        // If we get here, we have permission
        Log.p(Log.storage, Log.event, Log.success, "Photos access authorized")

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)

        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        Log.p(Log.storage, Log.read, "Found \(fetchResult.count) videos in Photos")

        var videoURLs: [URL] = []
        let dispatchGroup = DispatchGroup()

        fetchResult.enumerateObjects { asset, _, _ in
            dispatchGroup.enter()
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                defer { dispatchGroup.leave() }
                if let urlAsset = avAsset as? AVURLAsset {
                    // Clean the URL by removing any query parameters
                    if let cleanURL = URL(string: urlAsset.url.absoluteString.components(separatedBy: "#").first ?? "") {
                        videoURLs.append(cleanURL)
                        Log.p(Log.storage, Log.read, Log.success, "Successfully retrieved URL for video asset")
                    }
                } else {
                    Log.p(Log.storage, Log.read, Log.error, "Could not get URL for video asset")
                }
            }
        }

        dispatchGroup.wait()
        Log.p(Log.storage, Log.read, Log.success, "Retrieved \(videoURLs.count) video URLs")
        return videoURLs
    }

    func deleteVideo(at url: URL) -> AnyPublisher<Void, Error> {
        Log.p(Log.storage, Log.delete, "Attempting to delete video")

        return Future<Void, Error> { promise in
            // Find the PHAsset that corresponds to this URL
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)

            let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
            var assetToDelete: PHAsset?

            fetchResult.enumerateObjects { asset, _, stop in
                let dispatchGroup = DispatchGroup()
                dispatchGroup.enter()

                PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, _ in
                    defer { dispatchGroup.leave() }
                    if let urlAsset = avAsset as? AVURLAsset, urlAsset.url == url {
                        assetToDelete = asset
                        stop.pointee = true
                    }
                }

                dispatchGroup.wait()
            }

            guard let asset = assetToDelete else {
                Log.p(Log.storage, Log.read, Log.error, "Could not find video in Photos library")
                promise(.failure(NSError(domain: "LocalVideoService",
                                      code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "Video not found"])))
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
                Log.p(Log.storage, Log.delete, "Deleting video from Photos")
            } completionHandler: { success, error in
                if success {
                    Log.p(Log.storage, Log.delete, Log.success, "Video deleted successfully")
                    promise(.success(()))
                } else {
                    Log.p(Log.storage, Log.delete, Log.error, "Failed to delete video: \(error?.localizedDescription ?? "Unknown error")")
                    promise(.failure(error ?? NSError(domain: "LocalVideoService",
                                                    code: -1,
                                                    userInfo: [NSLocalizedDescriptionKey: "Failed to delete video"])))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func generateThumbnail(for videoURL: URL) -> AnyPublisher<UIImage?, Never> {
        Log.p(Log.storage, Log.start, "Starting thumbnail generation for \(videoURL.lastPathComponent)")

        return Future<UIImage?, Never> { promise in
            // Find the PHAsset that corresponds to this URL
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)

            let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
            Log.p(Log.storage, Log.read, "Searching for matching video asset")

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
                Log.p(Log.storage, Log.read, Log.error, "Could not find matching video asset")
                promise(.success(nil))
                return
            }

            Log.p(Log.storage, Log.read, Log.success, "Found matching video asset")

            // Request thumbnail using PHImageManager
            let size = CGSize(width: 300, height: 300)
            let thumbnailOptions = PHImageRequestOptions()
            thumbnailOptions.deliveryMode = .highQualityFormat
            thumbnailOptions.isNetworkAccessAllowed = true
            thumbnailOptions.isSynchronous = false

            Log.p(Log.storage, Log.read, "Requesting thumbnail generation")
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: thumbnailOptions
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    Log.p(Log.storage, Log.read, Log.error, "Thumbnail generation failed: \(error.localizedDescription)")
                    promise(.success(nil))
                    return
                }
                
                if let image = image {
                    Log.p(Log.storage, Log.read, Log.success, "Thumbnail generated successfully")
                    promise(.success(image))
                } else {
                    Log.p(Log.storage, Log.read, Log.error, "No thumbnail generated")
                    promise(.success(nil))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
