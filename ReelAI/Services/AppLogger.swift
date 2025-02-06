import Foundation
import os

/// AppLogger provides a unified logging interface for the ReelAI app.
/// It wraps Apple's unified logging system (os.Logger) and provides
/// a protocol-based extensible logging system.
enum Log {
    // MARK: - Protocols for Extensibility
    
    /// Protocol for log contexts
    protocol Context {
        var emoji: String { get }
        var name: String { get }
    }
    
    /// Protocol for log actions
    protocol Action {
        var emoji: String { get }
        var name: String { get }
    }
    
    /// Protocol for log alerts
    protocol Alert {
        var emoji: String { get }
        var name: String { get }
    }
    
    // MARK: - Built-in Contexts
    enum CoreContext: Context {
        case video, storage, upload, firebase, user, app, camera
        
        var emoji: String {
            switch self {
            case .video: return "🎥"
            case .storage: return "📼"
            case .upload: return "📤"
            case .firebase: return "🔥"
            case .user: return "👤"
            case .app: return "📱"
            case .camera: return "🎬"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    // MARK: - Built-in Actions
    enum CoreAction: Action {
        case start, stop, save, read, update, delete, event
        
        var emoji: String {
            switch self {
            case .start: return "▶️"
            case .stop: return "⏹️"
            case .save: return "💾"
            case .read: return "🔍"
            case .update: return "🔄"
            case .delete: return "🗑️"
            case .event: return "⚡️"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    // MARK: - Built-in Alerts
    enum CoreAlert: Alert {
        case error, warning, critical, success
        
        var emoji: String {
            switch self {
            case .error: return "❌"
            case .warning: return "⚠️"
            case .critical: return "🚨"
            case .success: return "✨"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    // MARK: - Log Filtering
    private static var enabledContexts: Set<String> = []
    private static var showSourceInfo = true
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.edgineer.ReelAI"
    
    static func enable(_ contexts: Context...) {
        enabledContexts.formUnion(contexts.map { $0.emoji })
    }
    
    static func disable(_ contexts: Context...) {
        enabledContexts.subtract(contexts.map { $0.emoji })
    }
    
    static func enableAll() {
        enabledContexts.removeAll()
    }
    
    static func toggleSourceInfo(_ enabled: Bool) {
        showSourceInfo = enabled
    }
    
    // MARK: - Logging Function
    
    static func p(
        _ context: Context,
        _ action: Action,
        _ alert: Alert? = nil,
        _ message: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        // Check if this context is enabled (if filters are active)
        if !enabledContexts.isEmpty && !enabledContexts.contains(context.emoji) {
            return
        }
        
        // Ensure we always have some output even if parameters are nil or invalid
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let thread = Thread.isMainThread ? "main" : Thread.current.description
        
        // Build log with safe fallbacks for everything
        var log = "[\(timestamp)][\(thread)]"
        
        // Add source info if enabled
        if showSourceInfo {
            let fileName = (file as NSString).lastPathComponent
            log += "[\(fileName):\(line)]"
        }
        
        // Add context and action
        log += " \(context.emoji) \(action.emoji)"
        
        // Add alert if present
        if let alert = alert {
            log += " \(alert.emoji)"
        }
        
        // Add message with fallback
        if let message = message, !message.isEmpty {
            log += " \(message)"
        } else {
            log += " <no message>"
        }
        
        // Both print and os_log for reliability, wrapped in do-catch
        do {
            print(log)
            let logger = Logger(subsystem: subsystem, category: context.name)
            logger.debug("\(log, privacy: .public)")
        } catch {
            // If all else fails, use print with a simple format
            print("🚨 Logger failed, raw message: \(message ?? "<no message>")")
        }
        #endif
    }
    
    // MARK: - Convenience Properties
    
    // Core contexts
    static let video = CoreContext.video
    static let storage = CoreContext.storage
    static let upload = CoreContext.upload
    static let firebase = CoreContext.firebase
    static let user = CoreContext.user
    static let app = CoreContext.app
    static let camera = CoreContext.camera
    
    // Core actions
    static let start = CoreAction.start
    static let stop = CoreAction.stop
    static let save = CoreAction.save
    static let read = CoreAction.read
    static let update = CoreAction.update
    static let delete = CoreAction.delete
    static let event = CoreAction.event
    
    // Core alerts
    static let error = CoreAlert.error
    static let warning = CoreAlert.warning
    static let critical = CoreAlert.critical
    static let success = CoreAlert.success
}

// MARK: - Feature-Specific Contexts

extension Log {
    // Social Features
    enum SocialContext: Log.Context {
        case feed, comments, likes, shares, trending
        
        var emoji: String {
            switch self {
            case .feed: return "📱"
            case .comments: return "💬"
            case .likes: return "❤️"
            case .shares: return "↗️"
            case .trending: return "📈"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    static let social_feed = SocialContext.feed
    static let social_comments = SocialContext.comments
    static let social_likes = SocialContext.likes
    static let social_shares = SocialContext.shares
    static let social_trending = SocialContext.trending
    
    // Story Generation Features
    enum StoryContext: Log.Context {
        case prompt, generation, editing
        
        var emoji: String {
            switch self {
            case .prompt: return "✍️"
            case .generation: return "📖"
            case .editing: return "✂️"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    static let story_prompt = StoryContext.prompt
    static let story_generation = StoryContext.generation
    static let story_editing = StoryContext.editing
    
    // Audio Features
    enum AudioContext: Log.Context {
        case voiceover, music, effects, mixing
        
        var emoji: String {
            switch self {
            case .voiceover: return "🎤"
            case .music: return "🎵"
            case .effects: return "🔊"
            case .mixing: return "🎚️"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    static let audio_voiceover = AudioContext.voiceover
    static let audio_music = AudioContext.music
    static let audio_effects = AudioContext.effects
    static let audio_mixing = AudioContext.mixing
}

extension AppLogger {
    // Emoji categories for print statements
    static let uiEmoji = "🖼️"
    static let cameraEmoji = "📸"
    static let videoEmoji = "📼"
    static let uploadEmoji = "📤"
    
    // Firestore categories
    static let dbEmoji = "🔥" // Firestore operations
    static let authEmoji = "🔑" // Authentication
    static let profileEmoji = "👤" // User profile operations
    
    static func dbEntry(_ message: String, collection: String? = nil) {
        print("🔥 📝 \(collection ?? ""): \(message)")
    }
    
    static func dbSuccess(_ message: String, collection: String? = nil) {
        print("🔥 ✅ \(collection ?? ""): \(message)")
    }
    
    static func dbError(_ message: String, error: Error, collection: String? = nil) {
        print("🔥 ❌ \(collection ?? ""): \(message)")
        print("🔥 💥 Error details: \(error.localizedDescription)")
    }
    
    static func dbQuery(_ message: String, collection: String) {
        print("🔥 🔍 \(collection): \(message)")
    }
    
    static func dbWrite(_ message: String, collection: String) {
        print("🔥 💾 \(collection): \(message)")
    }
    
    static func dbUpdate(_ message: String, collection: String) {
        print("🔥 ⚡️ \(collection): \(message)")
    }
    
    static func dbDelete(_ message: String, collection: String) {
        print("🔥 🗑️ \(collection): \(message)")
    }
}

// Example of how to extend with new contexts:
extension Log {
    enum AIContext: Log.Context {
        case training, inference, pipeline
        
        var emoji: String {
            switch self {
            case .training: return "🧠"
            case .inference: return "🤖"
            case .pipeline: return "⚙️"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    static let ai_training = AIContext.training
    static let ai_inference = AIContext.inference
    static let ai_pipeline = AIContext.pipeline
}

// Example usage:
// Log.p(Log.ai_training, Log.start, "Starting model training")
// Log.p(Log.ai_inference, Log.event, Log.warning, "Low confidence: \(score)")
