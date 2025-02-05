# ReelAI Logging Standards

## 1. Visual Logging Pattern

### Component Identifiers (First Emoji)
Each major component in the application uses a consistent first emoji as its "sheet" identifier:
- 📼 LocalVideoService operations
- 🖼️ Gallery/UI operations
- 📸 Camera operations
- 📤 Upload operations
- 🔄 Async/await operations

### Operation Types (Second Emoji)
The second emoji indicates the specific type of operation:

#### Setup & Configuration
- 🎬 Initialization/setup
- ⚙️ Configuration changes

#### File Operations
- 📁 Directory/file operations
- 💾 Save operations
- 🗑️ Delete operations
- 🔍 Search/fetch operations

#### Media Operations
- 🖼️ Thumbnail operations
- 📹 Recording operations
- ▶️ Start operations
- ⏹️ Stop operations

#### Status & Progress
- 📊 Progress/status updates
- ✅ Success completion
- 🧹 Cleanup operations

#### Authentication & Upload
- 🔑 Authentication operations
- 📤 Upload operations
- 🛑 Stop/shutdown operations

### Error Patterns
Errors use distinct patterns to stand out:
- ❌ 💥 Serious errors (crashes, system failures)
- ❌ 🔒 Authentication/permission errors
- ❌ 🚫 Validation/state errors
- ⚠️ Warnings

## 2. Implementation Guidelines

### Basic Usage
```swift
// Component initialization
print("📼 🎬 Initializing LocalVideoService")

// Operation progress
print("📼 💾 Starting video save operation")
print("📼 ✅ Saved video to \(path)")

// Errors
print("❌ 💥 Failed to save video: \(error.localizedDescription)")
```

### Context Guidelines
- Always include relevant identifiers (filenames, IDs) in logs
- For errors, include both the error description and any relevant state
- Use consistent terminology within each component
- Keep logs concise but informative

### Performance Considerations
- Avoid expensive string interpolation in production builds
- Consider using conditional compilation for verbose logs:
```swift
#if DEBUG
    print("📼 📊 Debug details: \(expensiveOperation())")
#endif
```

## 3. Integration with System Logger

While we use print statements with emojis for development visibility, we also maintain integration with Apple's unified logging system through AppLogger:

```swift
// System logging for errors
AppLogger.error(AppLogger.service, error)

// Debug logging
AppLogger.service.debug("Operation completed")
```

## 4. Best Practices

1. **Consistency**
   - Always use both emojis (component + operation)
   - Maintain consistent emoji usage within each component
   - Use the same format for similar operations

2. **Clarity**
   - Make logs easily scannable in console
   - Include relevant context but avoid verbosity
   - Use clear, action-oriented descriptions

3. **Error Handling**
   - Always log errors with both emojis and description
   - Include stack traces for serious errors
   - Log both the error and the state that caused it

4. **State Transitions**
   - Log important state changes
   - Include before/after values when relevant
   - Mark the completion of significant operations

## 5. Example Sequences

### Video Recording Flow
```swift
print("📸 🎬 Toggle recording called, current state: \(isRecording)")
print("📸 ▶️ Starting recording...")
print("📸 📹 Recording started, will save to: \(path)")
print("📸 ⏹️ Stopping recording...")
print("📸 💾 Recording stopped, file at: \(path)")
```

### Upload Flow
```swift
print("📤 📤 Starting upload process")
print("📤 🔑 Verifying authentication...")
print("📤 📊 Upload progress: 45%")
print("📤 ✅ Upload completed successfully")
```

### Error Handling
```swift
print("❌ 💥 Failed to save video: \(error)")
print("❌ 🔒 Upload failed: User not authenticated")
print("❌ 🚫 Invalid file format")
``` 