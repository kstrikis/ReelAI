# ReelAI Logging Standards

## Critical Logging Points

### 1. State Transitions
Always log when the application's state changes significantly:
```swift
// View lifecycle
print("🖼️ 🎬 View appearing - current state: \(state)")
print("🖼️ 🛑 View disappearing - cleaning up resources")

// User session changes
print("🔑 ⚡️ User session state changed: \(oldState) -> \(newState)")

// Data model updates
print("📊 ⚡️ Model updated: \(changes)")
```

### 2. Asynchronous Operations
Log the full lifecycle of async operations to track their progress:
```swift
// Operation start
print("🔄 🎬 Starting async operation: \(operationId)")

// Progress/state changes
print("🔄 📊 Operation \(operationId) progress: \(progress)%")

// Completion (success/failure)
print("🔄 ✅ Operation \(operationId) completed successfully")
print("❌ 💥 Operation \(operationId) failed: \(error)")
```

### 3. External Service Interactions
Track all interactions with external services:
```swift
// Requests
print("📤 🎬 Sending request to \(service): \(requestId)")

// Responses
print("📤 ✅ Received response for \(requestId)")
print("❌ 🚫 Request \(requestId) failed: \(statusCode)")
```

### 4. Resource Management
Monitor resource allocation and cleanup:
```swift
// Resource allocation
print("📸 🎬 Initializing camera session")
print("💾 📁 Creating temporary file at: \(path)")

// Resource cleanup
print("📸 🧹 Releasing camera session")
print("💾 🗑️ Cleaning up temp files")
```

### 5. Critical User Actions
Log important user interactions that trigger significant operations:
```swift
// Action initiation
print("👆 🎬 User initiated \(action)")

// Action completion
print("👆 ✅ User action completed: \(result)")
```

## Strategic Logging Approach

### 1. Breadcrumb Trail
Leave a clear trail of execution flow:
- Log entry and exit points of complex operations
- Track decision points and condition evaluations
- Note when expectations are met or violated

### 2. State Verification
Regularly verify and log system state:
- Check resource availability before use
- Validate data integrity at key points
- Confirm proper cleanup after operations

### 3. Error Recovery Points
Mark potential recovery points in the code:
- Log state before risky operations
- Track cleanup attempts after failures
- Note successful recovery steps

### 4. Performance Monitoring
Track timing of critical operations:
```swift
print("⏱️ 🎬 Starting operation at: \(startTime)")
// ... operation ...
print("⏱️ 📊 Operation took: \(duration)ms")
```

### 5. Memory Management
Monitor memory-critical operations:
```swift
print("📊 💾 Current memory usage: \(usage)MB")
print("📊 ⚠️ Memory threshold reached, initiating cleanup")
```

## Implementation Best Practices

### 1. Consistent Format
Each log should include:
- Component identifier (emoji)
- Operation type (emoji)
- Clear, descriptive message
- Relevant state/data
- Timestamp (when needed)

### 2. Log Levels
Use appropriate logging levels:
- Debug: Detailed flow information
- Info: Normal operation events
- Warning: Potential issues
- Error: Operation failures
- Critical: System-wide issues

### 3. Context Preservation
Include sufficient context:
```swift
print("📸 📊 Operation failed - Context:")
print("  - Current state: \(state)")
print("  - Last successful operation: \(lastOp)")
print("  - Resource status: \(resources)")
```

### 4. Recovery Information
Include information needed for recovery:
```swift
print("❌ 💥 Operation failed, recovery options:")
print("  - Retry count: \(retries)")
print("  - Fallback path: \(fallback)")
print("  - Cleanup needed: \(cleanup)")
```

## Key Points to Remember

1. **Log for Your Future Self**
   - Assume you won't remember the context
   - Include all information needed to understand the situation
   - Make logs searchable and meaningful

2. **Log for Time Pressure**
   - Make critical issues immediately visible
   - Include enough context to quickly identify problems
   - Group related logs logically

3. **Log for Recovery**
   - Include state information needed to recover
   - Log cleanup and retry attempts
   - Track resource allocation and release

4. **Log for Clarity**
   - Use consistent patterns
   - Make log messages self-explanatory
   - Include relevant IDs and timestamps

Remember: When in doubt, log more rather than less. You can always filter logs, but you can't recover information that wasn't logged.