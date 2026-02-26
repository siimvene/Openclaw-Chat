# AGENTS.md - Claw AI Chat (iOS)

Coding agent rules for the iOS app.

## Project Structure

```
Therin/
├── OpenClawApp.swift        # App entry point
├── Models/                   # Data models
│   ├── ChatMessage.swift
│   ├── Session.swift
│   └── SecurityAudit.swift
├── Views/                    # SwiftUI views
│   ├── ChatView.swift
│   ├── ContentView.swift
│   ├── VoiceView.swift
│   └── ...
├── Services/                 # Business logic
│   ├── GatewayClient.swift  # WebSocket connection
│   ├── SessionManager.swift
│   ├── VoiceInput.swift
│   └── TTSStreamer.swift
ShareExtension/              # Share sheet extension
```

## Code Quality (Avoid AI Slop)

Don't generate typical AI patterns that humans wouldn't write:

- ❌ Excessive comments explaining obvious code
- ❌ Unnecessary do/catch blocks on trusted internal calls
- ❌ Defensive nil checks for non-optional values
- ❌ Force unwrapping (`!`) to bypass optionals unsafely
- ❌ Over-engineering simple solutions
- ❌ **Using different names for the same concept** (e.g., `messageId`, `id`, `msgIdentifier`)
- ❌ Commented-out code blocks
- ❌ `print()` statements left in production code (use proper logging)

Match the existing style of the file you're editing.

## Swift/SwiftUI Conventions

### ✅ Always (Safe to Do)

- Use `@State`, `@Binding`, `@EnvironmentObject` appropriately
- Use `async/await` for async operations (not completion handlers)
- Use `Task { }` for async work from sync contexts
- Use `@MainActor` for UI updates
- Use `Codable` for JSON serialization
- Keep views small and composable
- Use `private` for internal state
- Use computed properties for derived values

### ⚠️ Ask First (Needs Approval)

- Adding new dependencies (Swift packages)
- Creating new architectural patterns
- Modifying the WebSocket protocol
- Changing Info.plist or entitlements
- Major refactoring across multiple files

### 🚫 Never (Forbidden)

- Force unwrap (`!`) without justification
- Use `try!` or `as!` without crash protection
- Block the main thread with synchronous operations
- Store sensitive data in UserDefaults (use Keychain)

## Boundaries

### View Layer
- Views should be declarative, not imperative
- Extract complex logic to ViewModels or Services
- Use `@ViewBuilder` for conditional view composition

### Service Layer
- GatewayClient handles all WebSocket communication
- SessionManager handles session persistence
- Services should be `@Observable` or `ObservableObject`

## Task Checklists

### Adding a New View

1. Create file in `Therin/Views/` with `PascalCase.swift` naming
2. Use `struct ViewName: View`
3. Inject dependencies via `@EnvironmentObject`
4. Add preview with `#Preview { }`
5. Test on multiple device sizes

### Adding a New Model

1. Create file in `Therin/Models/`
2. Make it `Codable` if it needs serialization
3. Make it `Identifiable` if used in lists
4. Use `let` for immutable properties

### Modifying WebSocket Protocol

1. Update `GatewayClient.swift`
2. Update corresponding server-side handling
3. Test connection/reconnection scenarios
4. Handle backwards compatibility

## Build Verification

Before committing:
```bash
xcodebuild -project ClawChat.xcodeproj -scheme ClawChat -destination "generic/platform=iOS" build
```

## Git Workflow

### Commit Messages

```
type(scope): description

feat(chat): add image message thumbnails
fix(voice): correct STT auto-stop behavior  
refactor(views): extract MessageBubble component
```
