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
        case start, stop, save, read, update, delete, event, exit, uploadAction
        
        var emoji: String {
            switch self {
            case .start: return "▶️"
            case .stop: return "⏹️"
            case .save: return "💾"
            case .read: return "🔍"
            case .update: return "🔄"
            case .delete: return "🗑️"
            case .event: return "⚡️"
            case .exit: return "🔚"
            case .uploadAction: return "📤"
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
    
    // MARK: - Logging Functions
    
    /// Log a message with context, action, alert, and message
    /// - Parameters:
    ///   - context: The area of the app generating the log
    ///   - action: The type of action being performed
    ///   - alert: The severity or status of the log
    ///   - message: The log message
    static func p(
        _ context: Context,
        _ action: Action,
        _ alert: Alert,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        internalLog(context: context, action: action, alert: alert, message: message, file: file, function: function, line: line)
        #endif
    }
    
    /// Log a message with just context, action, and message
    /// - Parameters:
    ///   - context: The area of the app generating the log
    ///   - action: The type of action being performed
    ///   - message: The log message
    static func p(
        _ context: Context,
        _ action: Action,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        internalLog(context: context, action: action, alert: nil, message: message, file: file, function: function, line: line)
        #endif
    }
    
    /// Log an error with context and message
    /// - Parameters:
    ///   - context: The area of the app generating the log
    ///   - error: The error to log
    ///   - message: Optional additional context message
    static func error(
        _ context: Context,
        _ error: Error,
        _ message: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let errorMessage = message.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
        internalLog(context: context, action: CoreAction.event, alert: CoreAlert.error, message: errorMessage, file: file, function: function, line: line)
        #endif
    }
    
    /// Log a success message with context
    /// - Parameters:
    ///   - context: The area of the app generating the log
    ///   - message: The success message
    static func success(
        _ context: Context,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        internalLog(context: context, action: CoreAction.event, alert: CoreAlert.success, message: message, file: file, function: function, line: line)
        #endif
    }
    
    /// Log a warning message with context
    /// - Parameters:
    ///   - context: The area of the app generating the log
    ///   - message: The warning message
    static func warning(
        _ context: Context,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        internalLog(context: context, action: CoreAction.event, alert: CoreAlert.warning, message: message, file: file, function: function, line: line)
        #endif
    }
    
    // Internal logging implementation
    private static func internalLog(
        context: Context,
        action: Action,
        alert: Alert?,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
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
        
        // Add message
        log += " \(message)"
        
        // Both print and os_log for reliability, wrapped in do-catch
        do {
            print(log)
            let logger = Logger(subsystem: subsystem, category: context.name)
            logger.debug("\(log, privacy: .public)")
        } catch {
            // If all else fails, use print with a simple format
            print("🚨 Logger failed, raw message: \(message)")
        }
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
    static let exit = CoreAction.exit
    static let uploadAction = CoreAction.uploadAction
    
    // Core alerts
    static let error = CoreAlert.error
    static let warning = CoreAlert.warning
    static let critical = CoreAlert.critical
    static let success = CoreAlert.success
}

// MARK: - Feature-Specific Contexts

extension Log {
    // Authentication Features
    enum AuthContext: Log.Context {
        case auth, session, token, provider
        
        var emoji: String {
            switch self {
            case .auth: return "🔐"
            case .session: return "🔑"
            case .token: return "🎟️"
            case .provider: return "🔒"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    static let auth = AuthContext.auth
    static let auth_session = AuthContext.session
    static let auth_token = AuthContext.token
    static let auth_provider = AuthContext.provider
    
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
    
    // Debug Features
    enum DebugContext: Log.Context {
        case debug, audit, cleanup
        
        var emoji: String {
            switch self {
            case .debug: return "🛠️"
            case .audit: return "🔍"
            case .cleanup: return "🧹"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    static let debug = DebugContext.debug
    static let debug_audit = DebugContext.audit
    static let debug_cleanup = DebugContext.cleanup
    
    // Debug Actions
    enum DebugAction: Log.Action {
        case scan, verify, clean, analyze, repair, validate
        
        var emoji: String {
            switch self {
            case .scan: return "🔎"
            case .verify: return "✅"
            case .clean: return "🧹"
            case .analyze: return "📊"
            case .repair: return "🔧"
            case .validate: return "🎯"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    static let scan = DebugAction.scan
    static let verify = DebugAction.verify
    static let clean = DebugAction.clean
    static let analyze = DebugAction.analyze
    static let repair = DebugAction.repair
    static let validate = DebugAction.validate
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

// MARK: - Example Usage
/*
 Basic logging:
 Log.p(Log.firebase, Log.start, "Starting service")
 Log.p(Log.firebase, Log.event, Log.error, "Service failed")
 
 Convenience methods:
 Log.error(Log.firebase, error, "Failed to initialize")
 Log.warning(Log.firebase, "Low memory condition")
 Log.success(Log.firebase, "Service started successfully")
 
 Context filtering:
 Log.enable(Log.firebase, Log.video)
 Log.disable(Log.storage)
 Log.enableAll()
 
 Source info:
 Log.toggleSourceInfo(true)  // Shows [File.swift:123]
 */
