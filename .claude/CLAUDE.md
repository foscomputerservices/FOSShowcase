# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

FOSShowcase is a full-stack M-V-VM suite demonstrating Swift-based applications across multiple platforms. The project showcases FOS Computer Services' open-source technologies using a shared ViewModels layer.

## Architecture

### Multi-Target Structure

The codebase is organized as a Swift Package with multiple executable and library targets:

1. **ViewModels** (Library): Shared view models using FOSMVVM framework
   - Core business logic and data structures
   - Platform-agnostic, shared across all frontends
   - Uses `@ViewModel`, `@LocalizedString` macros from FOSMVVM
   - Key types: `LandingPageViewModel`, `RequestableViewModel`

2. **WebServer** (Executable): Vapor-based REST API backend
   - Entry point: `Sources/WebServer/entrypoint.swift`
   - Configuration: `Sources/WebServer/configure.swift`
   - Routes: `Sources/WebServer/routes.swift`
   - Registers ViewModels as API endpoints using FOSMVVMVapor
   - YAML-based localization via `initYamlLocalization()`

3. **VaporLeafWebApp** (Executable): Vapor + Leaf template-based web frontend
   - Server-side rendered HTML using Leaf templates
   - Views in `Sources/VaporLeafWebApp/Views/`
   - Uses same ViewModels as other frontends

4. **IgniteWebApp** (Executable): Static site generator using Ignite framework
   - Site definition: `Sources/IgniteWebApp/Site.swift`
   - Pages in `Sources/IgniteWebApp/Pages/`
   - Layouts in `Sources/IgniteWebApp/Layouts/`

5. **SwiftUIApp**: Multi-platform SwiftUI application
   - Entry point: `Sources/SwiftUIApp/FOSShowcaseApp.swift`
   - Supports iOS, iPadOS, macOS, watchOS, tvOS, visionOS
   - Uses `.bind()` pattern from FOSMVVM to connect views to ViewModels
   - Environment configuration with `MVVMEnvironment` for deployment URLs

6. **SwiftUIViews**: Reusable SwiftUI views
   - Shared views like `LandingPageView`, `AboutFactView`, `ServiceItemView`

### Key Architectural Patterns

- **MVVM with FOSUtilities**: ViewModels are marked with `@ViewModel` macro and implement protocols like `RequestableViewModel`
- **Localization**: Uses YAML files in `Sources/Resources/` with `@LocalizedString` property wrapper
- **API Registration**: ViewModels auto-register as REST endpoints via `register(viewModel:)` in Vapor
- **Shared Resources**: `Sources/Resources/` contains localization and shared assets
- **Version Management**: `SystemVersion` enum manages app versioning

## Build & Test Commands

### Swift Package Manager

```bash
# Build all targets
swift build

# Run tests (macOS and Linux)
swift test

# Run specific test target
swift test --filter ViewModelTests
swift test --filter WebServerTests

# Build specific target
swift build --target WebServer
swift build --target VaporLeafWebApp
swift build --target IgniteWebApp
```

### Xcode

```bash
# Build iOS/watchOS/tvOS targets (requires Xcode)
xcodebuild -scheme FOSUtilities-Package -destination "generic/platform=ios" build
xcodebuild -scheme FOSUtilities-Package -destination "generic/platform=watchos" build
xcodebuild -scheme FOSUtilities-Package -destination "generic/platform=tvos" build

# With xcpretty for cleaner output
xcodebuild -scheme FOSUtilities-Package -destination "generic/platform=ios" build | xcpretty
```

### Running Applications

```bash
# Run WebServer (backend API)
swift run WebServer

# Run VaporLeafWebApp (web frontend with Leaf templates)
swift run VaporLeafWebApp

# Run IgniteWebApp (static site generator)
swift run IgniteWebApp
```

### Docker Deployment

The project includes multi-container Docker setup with Nginx reverse proxy:

```bash
# Build Docker images
docker-compose build

# Start all services (nginx, client, server, postgres)
docker-compose up

# Start specific service
docker-compose up server
docker-compose up client

# Stop all services
docker-compose down
```

**Docker Architecture**:
- `nginx`: Reverse proxy (ports 80, 443, 8081)
- `client`: VaporLeafWebApp on port 8082
- `server`: WebServer API on port 8083
- `postgres`: PostgreSQL database on port 5432

### Linting

SwiftLint runs automatically via `SwiftLintBuildToolPlugin` on macOS builds. Note: Plugin is disabled on non-macOS platforms (see conditional compilation in `Package.swift:127-133`).

## Dependencies

### FOS Frameworks
- **FOSUtilities** (https://github.com/foscomputerservices/FOSUtilities)
  - FOSFoundation: Core utilities
  - FOSMVVM: MVVM framework with macro support
  - FOSMVVMVapor: Vapor integration for ViewModels
  - FOSTesting: Testing utilities

### Third-Party Frameworks
- **Vapor 4.x**: Web framework for backend/web app
- **Leaf 4.x**: Templating engine for VaporLeafWebApp
- **Ignite**: Static site generator
- **SwiftLint**: Code linting via plugin

### Apple Frameworks
- **swift-testing**: New Swift native testing framework
- **swift-docc-plugin**: Documentation generation

## Project Configuration

- **Minimum macOS**: 14.0 (see `Package.swift:7`)
- **Swift Version**: 6.0.3 (see `.github/workflows/ci.yml:14`)
- **Swift Tools Version**: 6.1 (see `Package.swift:1`)
- **Platforms**: iOS, iPadOS, macOS, watchOS, tvOS, visionOS (Xcode project), macOS/Linux (SPM)

## Important Notes

### FOSMVVM Integration
- ViewModels use `@ViewModel` macro for conformance
- `@LocalizedString` properties auto-load from YAML resources
- `.bind()` method connects SwiftUI views to ViewModels
- `RequestableViewModel` protocol enables automatic REST API generation
- `ViewModelId` provides unique identifiers for ViewModel instances

### Resources & Localization
- Localization files: `Sources/Resources/*.yaml`
- WebServer initializes with `initYamlLocalization(bundle:resourceDirectoryName:)`
- Tests copy resources via `.copy("../../Sources/Resources")` in Package.swift

### Deployment URLs
SwiftUIApp uses `MVVMEnvironment` with different URLs per deployment:
- Production: `https://api.foscomputerservices.com:8081`
- Staging: `https://staging.foscomputerservices.com:8081`
- Debug: Configurable (defaults to staging)

### Swift-sh Shebang Issue
When generating scripts, use `\u{23}!` instead of `#!/` for shebangs due to swift-sh preprocessing bug.
