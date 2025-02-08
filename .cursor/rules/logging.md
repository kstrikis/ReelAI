# ReelAI Logging Rules

## 1. Core Logging System
We use a simple, reliable logging system through protocol-based extensible contexts. The logger supports two patterns:

1. Standard logging (no alert) - Use this for most logging needs:
```swift
Log.p(CONTEXT, ACTION, MESSAGE)
```

2. Alert logging - Use this ONLY for significant events:
```swift
Log.p(CONTEXT, ACTION, ALERT, MESSAGE)
```

Where:
- `CONTEXT`: Which part of the app (first emoji) - must conform to `Log.Context`
- `ACTION`: What's happening (second emoji) - must conform to `Log.Action`
- `ALERT`: Status/importance (third emoji) - must conform to `Log.Alert`, use ONLY for significant events
- `MESSAGE`: The actual log message

Example:
```swift
// Standard logging - use for routine operations
Log.p(Log.video, Log.start, "Starting playback")
Log.p(Log.firebase, Log.read, "Fetching user profile")

// Alert logging - use ONLY for significant events
Log.p(Log.video, Log.event, Log.error, "Playback failed: Network error")
Log.p(Log.firebase, Log.read, Log.warning, "Auth token expired")
```

### Alert Usage Guidelines
The third emoji (alert) should ONLY be used for:
1. Errors requiring immediate attention
   - Database operation failures
   - Network errors
   - Authentication failures
   - API errors
   
2. Warnings about user-impacting issues
   - Performance degradation
   - Resource limitations
   - Authentication state issues
   
3. Critical state changes
   - Service unavailability
   - Core functionality failures
   - Security-related events

DO NOT use alerts for:
- Successful operations
- Normal state changes
- Regular progress updates
- Expected transitions
- Routine events

## 2. Extending the Logging System

### Adding New Contexts
```swift
extension Log {
    enum YourContext: Log.Context {
        case featureA, featureB
        
        var emoji: String {
            switch self {
            case .featureA: return "💫"
            case .featureB: return "🌟"
            }
        }
        
        var name: String { String(describing: self) }
    }
    
    // Add convenience properties
    static let your_featureA = YourContext.featureA
    static let your_featureB = YourContext.featureB
}
```

### Built-in Contexts
- 🎥 Video Player (`Log.video`)
- 📼 Storage (`Log.storage`)
- 📤 Upload (`Log.upload`)
- 🔥 Firebase (`Log.firebase`)
- 👤 User (`Log.user`)
- 📱 App (`Log.app`)
- 🎬 Camera (`Log.camera`)
- 📱 Social Feed (`Log.social_feed`)
- 💬 Comments (`Log.social_comments`)
- ❤️ Likes (`Log.social_likes`)
- ↗️ Shares (`Log.social_shares`)
- 📈 Trending (`Log.social_trending`)
- ✍️ Story Prompt (`Log.story_prompt`)
- 📖 Story Generation (`Log.story_generation`)
- ✂️ Story Editing (`Log.story_editing`)
- 🎤 Voiceover (`Log.audio_voiceover`)
- 🎵 Music (`Log.audio_music`)
- 🔊 Effects (`Log.audio_effects`)
- 🎚️ Mixing (`Log.audio_mixing`)

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
1. Correct context protocol implementation
2. Appropriate emoji selection for new contexts
3. No sensitive data exposure
4. Meaningful message content
5. Performance considerations
6. Build configuration compliance

## 8. Testing Requirements

### Log Testing
- Verify logs appear in debug builds
- Verify logs don't appear in release builds
- Test filtering functionality
- Validate privacy compliance
- Test new context implementations

### Example Test
```swift
func testLogging() {
    Log.enable(Log.video)
    // Perform operation
    // Verify correct logs appeared
    // Verify other contexts didn't log
}
```

Remember: The logging system is extensible by design. When adding a new feature:
1. Create a new context enum conforming to `Log.Context`
2. Choose unique, descriptive emojis
3. Add convenience properties
4. Use consistently throughout the feature