# ReelAI Logging Standards

## Core Logging Pattern

We use a simple, reliable three-emoji logging system through protocol-based extensible contexts:
```swift
Log.p(CONTEXT, ACTION, ALERT?, MESSAGE)
```

Where:
- `CONTEXT`: Which part of the app (first emoji) - must conform to `Log.Context`
- `ACTION`: What's happening (second emoji) - must conform to `Log.Action`
- `ALERT`: Optional status/importance (third emoji) - must conform to `Log.Alert`
- `MESSAGE`: The actual log message

Example:
```swift
Log.p(Log.video, Log.start, Log.warning, "Buffer low for video: \(videoId)")
// Output: [10:45:30][main][VideoPlayer.swift:121] 🎥 ▶️ ⚠️ Buffer low for video: abc123
```

## Adding Logging to a New Feature

### 1. Define Your Context
First, extend `Log` with your feature's contexts:

```swift
extension Log {
    // For TikTok-style features
    enum SocialContext: Log.Context {
        case feed      // Main feed interactions
        case comments  // Comment system
        case likes    // Like/reaction system
        case shares   // Share functionality
        case trending // Trending/discovery
        
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
    
    // Add convenience properties
    static let social_feed = SocialContext.feed
    static let social_comments = SocialContext.comments
    static let social_likes = SocialContext.likes
    static let social_shares = SocialContext.shares
    static let social_trending = SocialContext.trending
}
```

### 2. Use Built-in Actions
Use the existing action emojis that best fit your needs:
- ▶️ `Log.start` - Starting an operation
- ⏹️ `Log.stop` - Ending an operation
- 💾 `Log.save` - Saving data
- 🔍 `Log.read` - Reading/querying data
- 🔄 `Log.update` - Updating state
- 🗑️ `Log.delete` - Deleting data
- ⚡️ `Log.event` - General events/triggers

### 3. Use Built-in Alerts
Use alerts to highlight important events:
- ❌ `Log.error` - Errors
- ⚠️ `Log.warning` - Warnings
- 🚨 `Log.critical` - Critical issues
- ✨ `Log.success` - Important successes

## Feature-Specific Examples

### Social Feed
```swift
// Feed loading
Log.p(Log.social_feed, Log.start, "Loading feed for user: \(userId)")
Log.p(Log.social_feed, Log.event, "Loaded \(count) videos")
Log.p(Log.social_feed, Log.error, "Feed failed to load: \(error)")

// Engagement
Log.p(Log.social_likes, Log.event, "User liked video: \(videoId)")
Log.p(Log.social_comments, Log.save, "New comment on video: \(videoId)")
Log.p(Log.social_shares, Log.event, "Video shared: \(videoId)")
```

### Story Generation
```swift
extension Log {
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
}

// Usage:
Log.p(Log.story_prompt, Log.start, "Processing user prompt")
Log.p(Log.story_generation, Log.event, "Story tokens generated: \(count)")
Log.p(Log.story_editing, Log.update, "Applied user edits")
```

### Audio Features
```swift
extension Log {
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

// Usage:
Log.p(Log.audio_voiceover, Log.start, "Starting voiceover generation")
Log.p(Log.audio_music, Log.event, "Background track selected")
Log.p(Log.audio_mixing, Log.update, "Adjusting levels")
```

## Filtering & Debug Tools

### Context Filtering
```swift
// Only show feed and comment logs
Log.enable(Log.social_feed, Log.social_comments)

// Hide music-related logs
Log.disable(Log.audio_music)

// Show all logs
Log.enableAll()
```

### Source Information
```swift
// Show [File.swift:123] in logs
Log.toggleSourceInfo(true)
```

## Best Practices

1. **Organize by Feature**
   - Create a new context enum for each major feature
   - Group related functionality within the same context
   - Use descriptive emoji that make logs easy to scan

2. **Log Key Points**
   - Start/end of operations
   - State changes
   - User interactions
   - Error conditions
   - Performance metrics

3. **Include Relevant IDs**
   - User IDs
   - Video/Content IDs
   - Session IDs
   - Request/Operation IDs

4. **Performance**
   - Logs are automatically disabled in Release builds
   - Use context filtering during development
   - Avoid expensive computations in log messages

Remember: The logging system is extensible by design. When adding a new feature, first create its logging context, then use it consistently throughout the feature's implementation.