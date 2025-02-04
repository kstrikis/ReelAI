──────────────────────────
1. Establish a Consistent Logging Framework
──────────────────────────
• Use Apple’s Unified Logging system (os_log) as our primary logging mechanism. With iOS 14+, the new Logger API (from the os package) is preferred over the older os_log since it adds type safety and a more streamlined API.
• Create a thin logging wrapper if needed so that we can swap or extend functionality (for example, to integrate with third-party telemetry services) with minimal impact on the rest of the codebase.
• Ensure the subsystem is consistently defined (typically using Bundle.main.bundleIdentifier) and choose categories to logically group logs (such as “networking”, “database”, “UI”, etc).

Example:
--------------------------------------------------
import os

struct AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.company.app"
    
    static func network(_ level: Logger.Level = .debug, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: "networking")
        logger.log(level: level, "\(message, privacy: .public)")
    }
    
    // Familiar wrappers for other modules (e.g., database, authentication) can be added similarly.
}
--------------------------------------------------

──────────────────────────
2. Define Logging Levels and Their Usage
──────────────────────────
• Debug (.debug):  
  – Use for verbose, development-time messages.  
  – Should be used to log detailed internal states and flow of execution only.  
  – In production builds, these should either be completely compiled out or be benign.

• Info (.info):  
  – Use for general information that might be useful during normal operations.  
  – Examples include key state transitions, startup/shutdown events, or noting user actions (only when necessary).

• Notice / Default (.default):  
  – Use for standard events that might be notable but aren’t indicative of problems.  
  – Good for marking successful operations.

• Error (.error):  
  – Use when an operation fails or an error condition occurs that might recover.  
  – Always include enough context (error codes, messages, or relevant identifiers) to diagnose issues.

• Fault (.fault):  
  – Use for serious, often unrecoverable conditions indicating systemic issues.  
  – Log these sparingly with thorough details as they might trigger crash reporting or alerts in monitoring systems.

──────────────────────────
3. Message Structure and Formatting
──────────────────────────
• Include context in every log message:
  – Use string interpolation to provide dynamic content.
  – Include method names, file or identifier tags if not already auto-included by your logging wrapper.
  – Standardize the prefix format, such as “[Module][Function] – Message” when relevant.

• Employ structured logging:
  – Take advantage of the Logger’s support for interpolated values with associated privacy settings.
  – Mark values as .public or .private accordingly.
  
Example:
--------------------------------------------------
logger.trace("Image loaded for identifier: \(identifier, privacy: .private)")
--------------------------------------------------

──────────────────────────
4. Handling Sensitive and Personally Identifiable Information (PII)
──────────────────────────
• Under no circumstances should sensitive data (e.g., plain text passwords, full credit card numbers, or personal information) be logged without proper masking or redaction.
• Use the Logger’s privacy settings (e.g., privacy: .private) to automatically redact sensitive values.
• Follow our company’s data security guidelines for any data that could be considered sensitive.

──────────────────────────
5. Build Configuration and Conditional Logging
──────────────────────────
• Use compile-time flags (e.g., #if DEBUG) to control the verbosity of logging, ensuring that verbose (debug-level) logs are not present in production builds.
• Consider having a runtime configuration flag for enabling or disabling elaborate logging if an in-app diagnostic mode is needed.
• For release builds, limit logs to Info, Error, and Fault levels.

Example:
--------------------------------------------------
#if DEBUG
    AppLogger.network(.debug, "Starting request to \(url)")
#endif
--------------------------------------------------

──────────────────────────
6. Performance Considerations
──────────────────────────
• Avoid expensive computations solely for the purpose of logging. Wrap detailed log computations behind a condition that first checks the log level.
• Do not block the main thread; the underlying os_log system is efficient, but any custom formatting or data processing in the code should be vetted for performance impact.
• Where necessary, offload heavy logging computations to background threads, especially if generating log messages involves non-trivial work.

──────────────────────────
7. Testing, Aggregation, and Monitoring
──────────────────────────
• Validate that log statements are present around critical flows and error handling paths.
• Document instructions for filtering and reading logs using the “Console” app or the “log” command-line tool.  
• Work with the QA/DevOps teams to forward or capture necessary logs for production monitoring (if additional telemetry is required beyond built-in device logging).

──────────────────────────
8. Code Review and Maintenance Guidelines
──────────────────────────
• Each new log statement should include enough context to be meaningful without being overly verbose.
• Reviewers must check for:
  – Consistent usage of logging levels.
  – Absence of sensitive data.
  – Appropriate logging granularity (avoiding excessive logging in tight loops or performance-critical code sections).
• Periodically review logging statements to remove or update obsolete logs as the application evolves.

──────────────────────────
9. Logging in Third-Party Libraries Integration
──────────────────────────
• When interfacing with third-party libraries that provide their own logging, consider wrapping or filtering their log output. This ensures consistency across the codebase and prevents potential exposure of sensitive debugging information.
• Document any additional log sources so that troubleshooting remains streamlined.

──────────────────────────
10. Documentation and In-Code Comments
──────────────────────────
• Maintain clear documentation (e.g., in the project wiki or code comments) that describes the logging standards including the expected log message format, level usage, and any platform-specific details.
• Where applicable, include inline comments that explain the context of a log message, particularly for error and fault logs.