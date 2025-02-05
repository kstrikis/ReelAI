import Foundation
import Combine
import AVFoundation
import UIKit

class LocalVideoService {
    static let shared = LocalVideoService()
    
    private init() {
        AppLogger.methodEntry(AppLogger.service)
        createVideoDirectory()
        AppLogger.methodExit(AppLogger.service)
    }
    
    // MARK: - Directory Management
    
    private var videosDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
    }
    
    private func createVideoDirectory() {
        AppLogger.methodEntry(AppLogger.service)
        do {
            try FileManager.default.createDirectory(at: self.videosDirectory, 
                                                  withIntermediateDirectories: true)
            AppLogger.service.debug("Created videos directory at \(self.videosDirectory.path)")
        } catch {
            AppLogger.error(AppLogger.service, error)
        }
        AppLogger.methodExit(AppLogger.service)
    }
    
    // MARK: - Video Management
    
    func saveVideo(from tempURL: URL) -> AnyPublisher<URL, Error> {
        AppLogger.methodEntry(AppLogger.service)
        return Future<URL, Error> { [self] promise in
            let filename = "\(UUID().uuidString).mp4"
            let destinationURL = self.videosDirectory.appendingPathComponent(filename)
            
            do {
                try FileManager.default.copyItem(at: tempURL, to: destinationURL)
                AppLogger.service.debug("Saved video to \(destinationURL.path)")
                promise(.success(destinationURL))
            } catch {
                AppLogger.error(AppLogger.service, error)
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getAllVideos() -> [URL] {
        AppLogger.methodEntry(AppLogger.service)
        do {
            let videoURLs = try FileManager.default.contentsOfDirectory(at: self.videosDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "mp4" }
                .sorted { url1, url2 in
                    let date1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1 > date2
                }
            AppLogger.service.debug("Found \(videoURLs.count) videos")
            return videoURLs
        } catch {
            AppLogger.error(AppLogger.service, error)
            return []
        }
    }
    
    func deleteVideo(at url: URL) -> AnyPublisher<Void, Error> {
        AppLogger.methodEntry(AppLogger.service)
        return Future<Void, Error> { promise in
            do {
                try FileManager.default.removeItem(at: url)
                AppLogger.service.debug("Deleted video at \(url.path)")
                promise(.success(()))
            } catch {
                AppLogger.error(AppLogger.service, error)
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func generateThumbnail(for videoURL: URL) -> AnyPublisher<UIImage?, Never> {
        AppLogger.methodEntry(AppLogger.service)
        return Future<UIImage?, Never> { promise in
            let asset = AVURLAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            imageGenerator.generateCGImageAsynchronously(for: .zero) { cgImage, _, error in
                if let error {
                    AppLogger.error(AppLogger.service, error)
                    promise(.success(nil))
                    return
                }
                
                if let cgImage {
                    let thumbnail = UIImage(cgImage: cgImage)
                    AppLogger.service.debug("Generated thumbnail for \(videoURL.lastPathComponent)")
                    promise(.success(thumbnail))
                } else {
                    AppLogger.service.debug("Failed to generate thumbnail")
                    promise(.success(nil))
                }
            }
        }
        .eraseToAnyPublisher()
    }
} 