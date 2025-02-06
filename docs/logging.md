# ReelAI Logging Standards

## Core Logging Pattern

We use a simple, reliable three-emoji logging system:
```swift
Log.p(CONTEXT, ACTION, ALERT?, MESSAGE)
```

Where:
- `CONTEXT`: Which part of the app (first emoji)
- `ACTION`: What's happening (second emoji)
- `ALERT`: Optional status/importance (third emoji)
- `MESSAGE`: The actual log message

Example:
```swift
Log.p(Log.video, Log.start, Log.warning, "Buffer low for video: \(videoId)")
// Output: [10:45:30][main][VideoPlayer.swift:121] 🎥 ▶️ ⚠️ Buffer low for video: abc123
```

## Context Emojis (First Position)
- 🎥 `Log.video` - Video Player
- 📼 `Log.storage` - Video Storage/Files
- 📤 `Log.upload` - Upload/Download
- 🔥 `Log.firebase` - Firebase/Firestore
- 👤 `Log.user` - User/Auth
- 📱 `Log.app` - App/UI
- 🎬 `Log.camera` - Camera

## Action Emojis (Second Position)
- ▶️ `Log.start` - Start/Begin
- ⏹️ `Log.stop` - Stop/End
- 💾 `Log.save` - Save/Write
- 🔍 `Log.read` - Read/Query
- 🔄 `Log.update` - Update/Change
- 🗑️ `Log.delete` - Delete
- ⚡️ `Log.event` - Event/Trigger

## Alert Emojis (Third Position, Optional)
- ❌ `Log.error` - Error
- ⚠️ `Log.warning` - Warning
- 🚨 `Log.critical` - Critical
- ✨ `Log.success` - Important Success

## Critical Logging Points

### 1. State Transitions
```swift
// View lifecycle
Log.p(Log.app, Log.start, "View appearing - state: \(state)")
Log.p(Log.app, Log.stop, "View disappearing - cleanup")

// User session
Log.p(Log.user, Log.event, "Session changed: \(oldState) -> \(newState)")

// Data updates
Log.p(Log.firebase, Log.update, "Model updated: \(changes)")
```

### 2. Async Operations
```swift
// Start
Log.p(Log.upload, Log.start, "Starting upload: \(operationId)")

// Progress
Log.p(Log.upload, Log.event, "Upload progress: \(progress)%")

// Completion
Log.p(Log.upload, Log.stop, Log.success, "Upload completed")
Log.p(Log.upload, Log.stop, Log.error, "Upload failed: \(error)")
```

### 3. Resource Management
```swift
// Allocation
Log.p(Log.camera, Log.start, "Initializing camera")
Log.p(Log.storage, Log.save, "Creating temp file: \(path)")

// Cleanup
Log.p(Log.camera, Log.stop, "Releasing camera")
Log.p(Log.storage, Log.delete, "Cleaning temp files")
```

## Filtering & Debug Tools

### Context Filtering
```swift
// Only show video and firebase logs
Log.enable(Log.video, Log.firebase)

// Hide storage logs
Log.disable(Log.storage)

// Show all logs
Log.enableAll()
```

### Source Information
```swift
// Show [File.swift:123] in logs
Log.toggleSourceInfo(true)
```

## Best Practices

1. **Always Include Context**
   - Use the appropriate context emoji
   - Add relevant IDs or identifiers
   - Include state information when relevant

2. **Be Consistent**
   - Follow the emoji pattern strictly
   - Use the predefined constants (Log.video, Log.start, etc.)
   - Don't create new emoji combinations

3. **Log Strategically**
   - Entry/exit of important methods
   - State changes and transitions
   - Error conditions and recovery attempts
   - Resource allocation/deallocation

4. **Debug Information**
   - Include file:line when debugging specific issues
   - Use alert emojis to highlight important logs
   - Filter by context when focusing on specific components

5. **Performance**
   - Logs are automatically disabled in Release builds
   - Use context filtering to reduce noise during development
   - Avoid expensive computations just for logging

## Example Scenarios

### Video Playback
```swift
Log.p(Log.video, Log.start, "Loading video: \(videoId)")
Log.p(Log.video, Log.event, "Buffer status: \(percentage)%")
Log.p(Log.video, Log.event, Log.warning, "Buffer below threshold")
Log.p(Log.video, Log.stop, "Playback ended")
```

### Authentication
```swift
Log.p(Log.user, Log.start, "Login attempt: \(email)")
Log.p(Log.user, Log.event, Log.error, "Invalid credentials")
Log.p(Log.user, Log.event, Log.success, "Login successful")
```

### File Operations
```swift
Log.p(Log.storage, Log.start, "Saving video")
Log.p(Log.storage, Log.save, "Created temp file")
Log.p(Log.storage, Log.event, "Processing: \(progress)%")
Log.p(Log.storage, Log.stop, Log.success, "Video saved")
```

Remember: When in doubt, log more rather than less. You can always filter logs, but you can't recover information that wasn't logged.