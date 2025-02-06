# ReelAI Logging Rules

## 1. Core Logging System
We use a simple, reliable three-emoji logging system through the `Log` enum:

```swift
Log.p(CONTEXT, ACTION, ALERT?, MESSAGE)
```

Example:
```swift
Log.p(Log.video, Log.start, Log.warning, "Buffer low for video: \(videoId)")
// Output: [10:45:30][main][VideoPlayer.swift:121] 🎥 ▶️ ⚠️ Buffer low for video: abc123
```

## 2. Logging Components

### Context Emoji (First Position)
Identifies the system component:
- 🎥 `Log.video` - Video Player
- 📼 `Log.storage` - Video Storage/Files
- 📤 `Log.upload` - Upload/Download
- 🔥 `Log.firebase` - Firebase/Firestore
- 👤 `Log.user` - User/Auth
- 📱 `Log.app` - App/UI
- 🎬 `Log.camera` - Camera

### Action Emoji (Second Position)
Describes the operation:
- ▶️ `Log.start` - Start/Begin
- ⏹️ `Log.stop` - Stop/End
- 💾 `Log.save` - Save/Write
- 🔍 `Log.read` - Read/Query
- 🔄 `Log.update` - Update/Change
- 🗑️ `Log.delete` - Delete
- ⚡️ `Log.event` - Event/Trigger

### Alert Emoji (Third Position, Optional)
Indicates importance/status:
- ❌ `Log.error` - Error
- ⚠️ `Log.warning` - Warning
- 🚨 `Log.critical` - Critical
- ✨ `Log.success` - Important Success

## 3. Build Configuration

### Debug vs Release
- Debug builds: Full logging enabled
- Release builds: Logs automatically disabled via #if DEBUG
```swift
#if DEBUG
    Log.p(Log.video, Log.event, "Debug-only detailed info")
#endif
```

### Filtering Options
```swift
// Enable specific contexts
Log.enable(Log.video, Log.firebase)

// Disable noisy components
Log.disable(Log.storage)

// Show everything
Log.enableAll()

// Toggle source info
Log.toggleSourceInfo(true)  // Shows [File.swift:123]
```

## 4. Privacy & Security

### Sensitive Data
- NEVER log authentication tokens
- NEVER log user passwords
- NEVER log complete credit card numbers
- NEVER log personal identifying information
- Use privacy markers in os_log when needed

```swift
// WRONG ❌
Log.p(Log.user, Log.event, "Password: \(password)")

// RIGHT ✅
Log.p(Log.user, Log.event, "Password length: \(password.count)")
```

## 5. Performance Guidelines

### Avoid Expensive Logging
```swift
// WRONG ❌
Log.p(Log.video, Log.event, "Stats: \(calculateExpensiveStats())")

// RIGHT ✅
#if DEBUG
    if Log.isEnabled(Log.video) {
        let stats = calculateExpensiveStats()
        Log.p(Log.video, Log.event, "Stats: \(stats)")
    }
#endif
```

### Batch Operations
```swift
// WRONG ❌
for item in items {
    Log.p(Log.storage, Log.event, "Processing \(item)")
}

// RIGHT ✅
Log.p(Log.storage, Log.start, "Processing \(items.count) items")
// ... processing ...
Log.p(Log.storage, Log.stop, "Completed processing \(items.count) items")
```

## 6. Required Logging Points

### Must Log
1. Application state transitions
2. User authentication events
3. Critical errors and exceptions
4. Resource allocation/deallocation
5. Network request start/completion
6. Database operations
7. File system operations

### Example Implementation
```swift
class VideoPlayer {
    func play() {
        Log.p(Log.video, Log.start, "Starting playback: \(videoId)")
        
        guard checkResources() else {
            Log.p(Log.video, Log.event, Log.error, "Resource check failed")
            return
        }
        
        // ... playing video ...
        
        Log.p(Log.video, Log.stop, "Playback completed")
    }
}
```

## 7. Code Review Requirements

Reviewers must verify:
1. Correct emoji pattern usage
2. No sensitive data exposure
3. Appropriate context selection
4. Meaningful message content
5. Performance considerations
6. Build configuration compliance

## 8. Testing Requirements

### Log Testing
- Verify logs appear in debug builds
- Verify logs don't appear in release builds
- Test filtering functionality
- Validate privacy compliance

### Example Test
```swift
func testLogging() {
    Log.enable(Log.video)
    // Perform operation
    // Verify correct logs appeared
    // Verify other contexts didn't log
}
```

Remember: The logging system should never fail or cause issues. It's designed to be bulletproof and help debug issues, not create them.