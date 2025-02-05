import Foundation
import os

/// AppLogger provides a unified logging interface for the ReelAI app.
/// It wraps Apple's unified logging system (os.Logger) to provide consistent,
/// categorized logging across the application.
struct AppLogger {
    // MARK: - Properties

    static let subsystem = Bundle.main.bundleIdentifier ?? "com.kstrikis.ReelAI"

    // MARK: - Category Loggers

    /// Logger for authentication-related events
    static let auth = Logger(subsystem: subsystem, category: "auth")

    // swiftlint:disable:next orphaned_doc_comment
    /// Logger for user interface events
    // swiftlint:disable:next identifier_name
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Logger for network operations
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Logger for data operations
    static let data = Logger(subsystem: subsystem, category: "data")

    /// Logger for service operations
    static let service = Logger(subsystem: subsystem, category: "service")

    // MARK: - Convenience Methods

    /// Logs method entry with parameters (if any)
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - method: The method name (defaults to current function name)
    ///   - params: Optional parameters to log
    static func methodEntry(
        _ logger: Logger,
        _ method: String = #function,
        params: [String: Any]? = nil
    ) {
        if let params {
            logger.debug("""
            ➡️ Entering \(method, privacy: .public) with params: \
            \(String(describing: params), privacy: .private)
            """)
        } else {
            logger.debug("➡️ Entering \(method, privacy: .public)")
        }
    }

    /// Logs method exit with result (if any)
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - method: The method name (defaults to current function name)
    ///   - result: Optional result to log
    static func methodExit(
        _ logger: Logger,
        _ method: String = #function,
        result: Any? = nil
    ) {
        if let result {
            logger.debug("""
            ⬅️ Exiting \(method, privacy: .public) with result: \
            \(String(describing: result), privacy: .private)
            """)
        } else {
            logger.debug("⬅️ Exiting \(method, privacy: .public)")
        }
    }

    /// Logs an error with additional context
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - error: The error to log
    ///   - context: Additional context about where/why the error occurred
    static func error(
        _ logger: Logger,
        _ error: Error,
        context: String? = nil
    ) {
        if let context {
            logger.error("❌ Error in \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            logger.error("❌ Error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Logs method entry with a message and source information
    /// - Parameters:
    ///   - message: The message to log
    ///   - file: Source file name (automatically provided)
    ///   - function: Function name (automatically provided)
    ///   - line: Line number (automatically provided)
    func methodEntry(
        _ message: String,
        file _: String = #file,
        function _: String = #function,
        line _: Int = #line
    ) {
        AppLogger.debug("\(message)")
    }

    /// Logs method exit with a message and source information
    /// - Parameters:
    ///   - message: The message to log
    ///   - file: Source file name (automatically provided)
    ///   - function: Function name (automatically provided)
    ///   - line: Line number (automatically provided)
    func methodExit(
        _ message: String,
        file _: String = #file,
        function _: String = #function,
        line _: Int = #line
    ) {
        AppLogger.debug("\(message)")
    }
}

// MARK: - Debug Convenience Extensions

#if DEBUG
    extension AppLogger {
        /// Logs a debug message with the file and line number
        static func debug(
            _ message: String,
            file: String = #file,
            line: Int = #line
        ) {
            let fileName = (file as NSString).lastPathComponent
            print("🪲 DEBUG: \(fileName):\(line) - \(message)")  // Changed to print
            
            // Also log to system logger for good measure
            let logger = Logger(subsystem: subsystem, category: "debug")
            logger.debug("📝 \(fileName):\(line) - \(message, privacy: .public)")
        }
    }
#endif

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
