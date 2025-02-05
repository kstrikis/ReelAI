import Foundation
import Combine
import AVFoundation
import UIKit
import Photos

class LocalVideoService {
    static let shared = LocalVideoService()
    
    private init() {
        print("📼 🎬 Initializing LocalVideoService")
        print("📼 ✅ LocalVideoService initialized")
    }
    
    func saveVideo(from tempURL: URL) -> AnyPublisher<URL, Error> {
        print("📼 💾 Starting video save operation")
        
        return Future<URL, Error> { promise in
            // Verify the temp file exists and is readable
            guard FileManager.default.fileExists(atPath: tempURL.path) else {
                print("❌ 🚫 Temp file not accessible: \(tempURL.path)")
                promise(.failure(NSError(domain: "LocalVideoService", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "Video file not accessible"])))
                return
            }
            
            // Function to attempt save with retry
            func attemptSave(retryCount: Int = 0, maxRetries: Int = 3) {
                print("📼 📝 Attempting to save video (attempt \(retryCount + 1)/\(maxRetries + 1))")
                
                Task {
                    do {
                        // First verify we can read the file
                        let videoData = try Data(contentsOf: tempURL, options: .alwaysMapped)
                        print("📼 📊 Video file size: \(Double(videoData.count) / 1_000_000.0)MB")
                        
                        try await PHPhotoLibrary.shared().performChanges {
                            print("📼 📝 Creating Photos asset...")
                            let request = PHAssetCreationRequest.forAsset()
                            request.addResource(with: .video, fileURL: tempURL, options: nil)
                        }
                        print("📼 ✅ Video saved to Photos")
                        promise(.success(tempURL))
                    } catch {
                        print("❌ 💥 Save attempt \(retryCount + 1) failed: \(error.localizedDescription)")
                        if let phError = error as? PHPhotosError {
                            print("❌ 💥 Photos error code: \(phError.errorCode)")
                        }
                        
                        // If we haven't maxed out retries, wait and try again
                        if retryCount < maxRetries {
                            print("📼 ⏳ Waiting before retry...")
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
        print("📼 🔍 Fetching videos from Photos")
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        print("📼 📊 Found \(fetchResult.count) videos in Photos")
        
        var videoURLs: [URL] = []
        let dispatchGroup = DispatchGroup()
        
        fetchResult.enumerateObjects { asset, _, _ in
            dispatchGroup.enter()
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                defer { dispatchGroup.leave() }
                guard let urlAsset = avAsset as? AVURLAsset else { return }
                videoURLs.append(urlAsset.url)
            }
        }
        
        dispatchGroup.wait()
        print("📼 ✅ Retrieved \(videoURLs.count) video URLs")
        return videoURLs
    }
    
    func deleteVideo(at url: URL) -> AnyPublisher<Void, Error> {
        print("📼 🗑️ Attempting to delete video")
        
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
                print("❌ 🚫 Could not find video in Photos library")
                promise(.failure(NSError(domain: "LocalVideoService", 
                                      code: -1, 
                                      userInfo: [NSLocalizedDescriptionKey: "Video not found"])))
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
                print("📼 🗑️ Deleting video from Photos...")
            } completionHandler: { success, error in
                if success {
                    print("📼 ✅ Video deleted successfully")
                    promise(.success(()))
                } else {
                    print("❌ 💥 Failed to delete video: \(error?.localizedDescription ?? "Unknown error")")
                    promise(.failure(error ?? NSError(domain: "LocalVideoService", 
                                                    code: -1, 
                                                    userInfo: [NSLocalizedDescriptionKey: "Failed to delete video"])))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func generateThumbnail(for videoURL: URL) -> AnyPublisher<UIImage?, Never> {
        print("📼 🖼️ Starting thumbnail generation for \(videoURL.lastPathComponent)")
        return Future<UIImage?, Never> { promise in
            Task {
                let asset = AVURLAsset(url: videoURL)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 300, height: 300)
                
                do {
                    let cgImage = try await imageGenerator.image(at: .zero).image
                    let thumbnail = UIImage(cgImage: cgImage)
                    print("📼 ✅ Generated thumbnail")
                    promise(.success(thumbnail))
                } catch {
                    print("❌ 💥 Failed to generate thumbnail: \(error.localizedDescription)")
                    promise(.success(nil))
                }
            }
        }
        .eraseToAnyPublisher()
    }
} 