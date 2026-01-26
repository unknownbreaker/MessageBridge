# MessageProcessor Chain Design

**Date:** 2026-01-26
**Status:** Approved
**Goal:** Extract message processing into a composable chain of processors that enrich messages with detected codes, phone numbers, mentions, and emoji flags.

---

## Problem

Messages currently flow from the database to clients without any processing or enrichment. There's no way to:
- Detect 2FA verification codes for quick copy
- Highlight phone numbers
- Parse @mentions
- Flag emoji-only messages for enlarged display

## Design Goals

1. **Composable** — Independent processors that can be added/removed
2. **Extensible** — Easy to add new processors (LinkUnfurler later)
3. **Testable** — Each processor can be unit tested in isolation
4. **Non-blocking** — All processors are synchronous (no network calls in v1)

## Scope

**In scope (v1):**
- CodeDetector — 2FA/verification codes
- PhoneNumberDetector — Phone number patterns
- MentionExtractor — @username patterns
- EmojiEnlarger — Emoji-only message detection

**Out of scope (future):**
- LinkUnfurler — URL metadata fetching (requires async/network)

---

## Core Types

### ProcessedMessage

Wraps a Message with enrichments:

```swift
// Sources/MessageBridgeCore/Models/ProcessedMessage.swift

public struct ProcessedMessage: Codable, Sendable {
    /// The original message from the database
    public let message: Message

    /// Detected verification/2FA codes
    public var detectedCodes: [DetectedCode]

    /// Text highlights (codes, phone numbers, etc.)
    public var highlights: [TextHighlight]

    /// Detected @mentions
    public var mentions: [Mention]

    /// Whether this is an emoji-only message (for enlarged display)
    public var isEmojiOnly: Bool

    public init(message: Message) {
        self.message = message
        self.detectedCodes = []
        self.highlights = []
        self.mentions = []
        self.isEmojiOnly = false
    }
}
```

### Supporting Types

```swift
// Sources/MessageBridgeCore/Models/DetectedCode.swift

public struct DetectedCode: Codable, Sendable, Equatable {
    public let value: String
    public let confidence: Confidence

    public enum Confidence: String, Codable, Sendable {
        case high    // Context words + code pattern
        case medium  // Code pattern only
    }

    public init(value: String, confidence: Confidence) {
        self.value = value
        self.confidence = confidence
    }
}
```

```swift
// Sources/MessageBridgeCore/Models/TextHighlight.swift

public struct TextHighlight: Codable, Sendable, Equatable {
    public let text: String
    public let startIndex: Int
    public let endIndex: Int
    public let type: HighlightType

    public enum HighlightType: String, Codable, Sendable {
        case code
        case phoneNumber
        case mention
    }

    public init(text: String, startIndex: Int, endIndex: Int, type: HighlightType) {
        self.text = text
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.type = type
    }
}
```

```swift
// Sources/MessageBridgeCore/Models/Mention.swift

public struct Mention: Codable, Sendable, Equatable {
    public let text: String      // "@john"
    public let handle: String?   // Phone/email if resolvable

    public init(text: String, handle: String? = nil) {
        self.text = text
        self.handle = handle
    }
}
```

---

## Protocol and Chain

### MessageProcessor Protocol

```swift
// Sources/MessageBridgeCore/Protocols/MessageProcessor.swift

public protocol MessageProcessor: Identifiable, Sendable {
    /// Unique identifier for this processor
    var id: String { get }

    /// Higher priority runs first
    var priority: Int { get }

    /// Process the message, returning an enriched version
    func process(_ message: ProcessedMessage) -> ProcessedMessage
}
```

### ProcessorChain

```swift
// Sources/MessageBridgeCore/Processors/ProcessorChain.swift

public final class ProcessorChain: @unchecked Sendable {
    public static let shared = ProcessorChain()

    private var processors: [any MessageProcessor] = []
    private let lock = NSLock()

    private init() {}

    /// Register a processor
    public func register(_ processor: any MessageProcessor) {
        lock.lock()
        defer { lock.unlock() }
        processors.append(processor)
        processors.sort { $0.priority > $1.priority }
    }

    /// Process a message through all registered processors
    public func process(_ message: Message) -> ProcessedMessage {
        lock.lock()
        let sortedProcessors = processors
        lock.unlock()

        var result = ProcessedMessage(message: message)
        for processor in sortedProcessors {
            result = processor.process(result)
        }
        return result
    }

    /// All registered processors (for inspection)
    public var all: [any MessageProcessor] {
        lock.lock()
        defer { lock.unlock() }
        return processors
    }

    /// Reset for testing
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        processors.removeAll()
    }
}
```

---

## Processor Implementations

### CodeDetector

```swift
// Sources/MessageBridgeCore/Processors/CodeDetector.swift

public struct CodeDetector: MessageProcessor {
    public let id = "code-detector"
    public let priority = 200

    private let codePattern = #"\b(\d{4,8})\b"#
    private let contextWords = [
        "code", "verify", "verification", "confirm", "otp",
        "pin", "password", "passcode", "2fa", "mfa",
        "security", "authentication", "login", "sign in"
    ]

    public init() {}

    public func process(_ message: ProcessedMessage) -> ProcessedMessage {
        guard let text = message.message.text else { return message }

        var result = message
        let lowercased = text.lowercased()
        let hasContext = contextWords.contains { lowercased.contains($0) }

        guard hasContext else { return message }

        guard let regex = try? NSRegularExpression(pattern: codePattern) else {
            return message
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }

            let code = String(text[swiftRange])
            result.detectedCodes.append(DetectedCode(value: code, confidence: .high))
            result.highlights.append(TextHighlight(
                text: code,
                startIndex: text.distance(from: text.startIndex, to: swiftRange.lowerBound),
                endIndex: text.distance(from: text.startIndex, to: swiftRange.upperBound),
                type: .code
            ))
        }

        return result
    }
}
```

### PhoneNumberDetector

```swift
// Sources/MessageBridgeCore/Processors/PhoneNumberDetector.swift

public struct PhoneNumberDetector: MessageProcessor {
    public let id = "phone-number-detector"
    public let priority = 150

    public init() {}

    public func process(_ message: ProcessedMessage) -> ProcessedMessage {
        guard let text = message.message.text else { return message }

        var result = message

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
        let range = NSRange(text.startIndex..., in: text)

        detector?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match,
                  let swiftRange = Range(match.range, in: text) else { return }

            let phone = String(text[swiftRange])
            result.highlights.append(TextHighlight(
                text: phone,
                startIndex: text.distance(from: text.startIndex, to: swiftRange.lowerBound),
                endIndex: text.distance(from: text.startIndex, to: swiftRange.upperBound),
                type: .phoneNumber
            ))
        }

        return result
    }
}
```

### MentionExtractor

```swift
// Sources/MessageBridgeCore/Processors/MentionExtractor.swift

public struct MentionExtractor: MessageProcessor {
    public let id = "mention-extractor"
    public let priority = 100

    private let mentionPattern = #"@(\w+)"#

    public init() {}

    public func process(_ message: ProcessedMessage) -> ProcessedMessage {
        guard let text = message.message.text else { return message }

        var result = message

        guard let regex = try? NSRegularExpression(pattern: mentionPattern) else {
            return message
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }

            let mention = String(text[swiftRange])
            result.mentions.append(Mention(text: mention, handle: nil))
            result.highlights.append(TextHighlight(
                text: mention,
                startIndex: text.distance(from: text.startIndex, to: swiftRange.lowerBound),
                endIndex: text.distance(from: text.startIndex, to: swiftRange.upperBound),
                type: .mention
            ))
        }

        return result
    }
}
```

### EmojiEnlarger

```swift
// Sources/MessageBridgeCore/Processors/EmojiEnlarger.swift

public struct EmojiEnlarger: MessageProcessor {
    public let id = "emoji-enlarger"
    public let priority = 50

    public init() {}

    public func process(_ message: ProcessedMessage) -> ProcessedMessage {
        guard let text = message.message.text else { return message }

        var result = message

        // Check if message contains only emoji (and optional whitespace)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isAllEmoji = !trimmed.isEmpty && trimmed.allSatisfy { $0.isEmoji }

        // Only enlarge if 1-5 emoji (not a wall of emoji)
        let emojiCount = trimmed.filter { $0.isEmoji }.count
        result.isEmojiOnly = isAllEmoji && emojiCount <= 5

        return result
    }
}

// Helper extension
extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
```

---

## Integration Points

### MessageChangeDetector

```swift
// In checkForNewMessages()

for (message, _, senderAddress) in newMessages {
    let processed = ProcessorChain.shared.process(message)
    await onNewMessage?(processed, senderAddress)
    // ...
}
```

Handler signature changes from:
```swift
(Message, String?) async -> Void
```
to:
```swift
(ProcessedMessage, String?) async -> Void
```

### Routes.swift

```swift
// GET /conversations/:id/messages
let messages = try await database.fetchMessages(...)
let processed = messages.map { ProcessorChain.shared.process($0) }
return MessagesResponse(messages: processed, nextCursor: nextCursor)
```

### ServerApp.swift

```swift
private func setupMessageProcessors() {
    ProcessorChain.shared.register(CodeDetector())
    ProcessorChain.shared.register(PhoneNumberDetector())
    ProcessorChain.shared.register(MentionExtractor())
    ProcessorChain.shared.register(EmojiEnlarger())
}

// Call in init()
```

### API Response Changes

- `MessagesResponse.messages` type changes from `[Message]` to `[ProcessedMessage]`
- WebSocket `NewMessageData` changes to use `ProcessedMessage`
- Clients receive enriched data with highlights, codes, mentions, etc.

---

## File Structure

**New files:**

```
MessageBridgeServer/Sources/MessageBridgeCore/
├── Models/
│   ├── ProcessedMessage.swift
│   ├── DetectedCode.swift
│   ├── TextHighlight.swift
│   └── Mention.swift
├── Protocols/
│   └── MessageProcessor.swift
├── Processors/
│   ├── ProcessorChain.swift
│   ├── CodeDetector.swift
│   ├── PhoneNumberDetector.swift
│   ├── MentionExtractor.swift
│   └── EmojiEnlarger.swift

Tests/MessageBridgeCoreTests/
├── Processors/
│   ├── ProcessorChainTests.swift
│   ├── CodeDetectorTests.swift
│   ├── PhoneNumberDetectorTests.swift
│   ├── MentionExtractorTests.swift
│   └── EmojiEnlargerTests.swift
```

**Files to modify:**

| File | Change |
|------|--------|
| `MessageChangeDetector.swift` | Use ProcessedMessage in handler |
| `Routes.swift` | Process messages before returning |
| `ServerApp.swift` | Register processors at startup |
| `WebSocketManager.swift` | Broadcast ProcessedMessage |
| `WebSocketMessages.swift` | Update NewMessageData type |
| `APIResponses.swift` | Update MessagesResponse type |

---

## Migration Steps

1. Create model types (ProcessedMessage, DetectedCode, TextHighlight, Mention)
2. Create MessageProcessor protocol
3. Create ProcessorChain
4. Implement CodeDetector with tests
5. Implement PhoneNumberDetector with tests
6. Implement MentionExtractor with tests
7. Implement EmojiEnlarger with tests
8. Update API response types
9. Integrate into MessageChangeDetector
10. Integrate into Routes.swift
11. Register processors in ServerApp.swift
12. Update CLAUDE.md migration table

---

## Future Extensions

**Adding LinkUnfurler (async):**

Will require changes to support async processors:
```swift
protocol AsyncMessageProcessor: MessageProcessor {
    func process(_ message: ProcessedMessage) async -> ProcessedMessage
}
```

ProcessorChain would run sync processors immediately, then async processors in parallel, updating messages via WebSocket when complete.
