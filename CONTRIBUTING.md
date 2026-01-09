# Contributing to MessageBridge

Thank you for your interest in contributing to MessageBridge! This document provides guidelines and instructions for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch from `main`
4. Make your changes following our conventions
5. Write tests for new functionality
6. Ensure all tests pass
7. Submit a pull request

## Development Setup

### Prerequisites

- macOS 13+
- Xcode 15+
- Swift 5.9+

### Building

```bash
# Server
cd MessageBridgeServer
swift build
swift test

# Client
cd MessageBridgeClient
swift build
swift test
```

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/) for automatic changelog generation and semantic versioning.

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description | Version Bump |
|------|-------------|--------------|
| `feat` | A new feature | Minor (0.X.0) |
| `fix` | A bug fix | Patch (0.0.X) |
| `docs` | Documentation only changes | None |
| `style` | Formatting, missing semicolons, etc. | None |
| `refactor` | Code change that neither fixes a bug nor adds a feature | None |
| `perf` | Performance improvement | Patch (0.0.X) |
| `test` | Adding or updating tests | None |
| `chore` | Maintenance tasks, dependencies | None |
| `ci` | CI/CD changes | None |
| `build` | Build system changes | None |

### Scopes

Use one of these scopes to indicate which part of the codebase is affected:

- `server` - MessageBridgeServer changes
- `client` - MessageBridgeClient changes
- `docs` - Documentation changes
- `ci` - CI/CD workflow changes
- `scripts` - Build/deployment script changes

### Examples

```bash
# New feature
feat(client): add Tailscale status indicator in toolbar

# Bug fix
fix(server): handle nil message text in WebSocket handler

# Documentation
docs: update installation instructions for macOS Sonoma

# Refactoring
refactor(client): extract message bubble into reusable component

# Multiple scopes (use comma)
feat(server,client): add version endpoint and display

# Breaking change (triggers major version bump)
feat(server)!: rename /send endpoint to /messages

BREAKING CHANGE: The /send endpoint has been renamed to /messages.
Update your client configuration accordingly.
```

### Commit Message Guidelines

1. **Use imperative mood** in the subject line ("add feature" not "added feature")
2. **Keep subject line under 72 characters**
3. **Capitalize the subject line**
4. **Do not end the subject line with a period**
5. **Separate subject from body with a blank line**
6. **Use the body to explain what and why** (not how)

### Breaking Changes

For breaking changes, either:
- Add `!` after the type/scope: `feat(server)!: change API response format`
- Add a `BREAKING CHANGE:` footer explaining the change

## Code Style

### Swift Conventions

- Use `actor` for thread-safe classes
- Use `@MainActor` for ViewModels that update UI
- Prefer `async/await` over callbacks
- Models should be `Codable`, `Identifiable`, and `Sendable`
- Use protocols for dependency injection and testability

### Testing

- Write tests first (TDD approach)
- Each test should describe a specific behavior
- Name tests descriptively: `testConnect_whenServerUnavailable_setsStatusToDisconnected`
- Mock external dependencies

### Logging

Use the built-in logging system instead of `print()`:

```swift
logDebug("Loaded \(count) conversations")
logInfo("WebSocket connection established")
logWarning("Retrying connection...")
logError("Connection failed", error: error)
```

## Pull Request Process

1. **Update documentation** if your change affects user-facing features
2. **Add tests** for new functionality
3. **Ensure CI passes** - all tests must pass
4. **Use a descriptive PR title** following commit conventions
5. **Reference any related issues** in the PR description

### PR Title Format

Use the same format as commit messages:
```
feat(client): add dark mode support
fix(server): resolve memory leak in WebSocket handler
```

## Versioning

We use [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes
- **MINOR** (0.X.0): New features (backwards compatible)
- **PATCH** (0.0.X): Bug fixes (backwards compatible)

Version bumps are determined automatically from commit messages:
- `feat:` commits bump the minor version
- `fix:` and `perf:` commits bump the patch version
- `BREAKING CHANGE:` or `!` bumps the major version

## Questions?

If you have questions, feel free to:
- Open an issue for discussion
- Check existing issues and documentation

Thank you for contributing!
