# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-12-XX

### Added
- **Singleton Pattern**: Global `pug` instance for convenient access
- **Automatic Setup**: Pug.js installation and initialization happens automatically on first use
- **Simplified API**: No need to manually check availability or call setup
- `dispose()` method as alias for `shutdown()` with cleaner semantics
- New `PugInstance` class wrapping the static `PugServer` methods
- Automatic initialization tracking to prevent redundant setup calls
- **Node.js/npm requirement warning**: Added explicit warning in installation documentation

### Changed
- **BREAKING**: Primary API is now the global `pug` instance instead of static `PugServer` methods
- **BREAKING**: Teardown method renamed from `shutdown()` to `dispose()` 
- **BREAKING**: `PugServer` class is no longer exported - users must use the `pug` singleton
- **BREAKING**: `setup()` and `isAvailable()` methods are now private - setup is fully automatic
- Default setup now happens silently (non-verbose) for better user experience
- Improved documentation with singleton pattern examples
- Updated quick start guide to show zero-configuration usage
- Simplified example files to demonstrate automatic setup
- Updated all tests to use new singleton API

### Removed
- **BREAKING**: Manual setup documentation section (setup is now automatic)
- **BREAKING**: Public access to `setup()` and `isAvailable()` methods
- **BREAKING**: Direct access to `PugServer` static methods
- Setup example file (replaced with automatic setup demonstration)

### Improved
- User experience: Just `import` and use `pug.render()` - no setup required
- API consistency: Single instance pattern matches common Dart conventions
- Resource management: Clearer separation between dispose and automatic restart
- Documentation clarity: Removed confusing manual setup options

### Migration Guide
```dart
// Old API (no longer available)
if (!await PugServer.isAvailable()) {
  await PugServer.setup();
}
final html = await PugServer.render('h1 Hello');
await PugServer.shutdown();

// New API (only way to use the library)
final html = await pug.render('h1 Hello');
await pug.dispose();
```

## [0.0.1] - 2024-06-04

### Added
- Initial release of pug_dart
- High-performance persistent Node.js server with Unix domain sockets
- Support for `PugServer.render()` - render Pug template strings
- Support for `PugServer.renderFile()` - render Pug template files using File objects
- Support for `PugServer.compile()` - compile and render templates in one step
- Support for `PugServer.compileFile()` - compile and render files in one step
- Automatic Pug.js installation via `PugServer.setup()`
- Availability checking with `PugServer.isAvailable()`
- Graceful server shutdown with `PugServer.shutdown()`
- Type-safe error handling with `FileSystemException` for file errors and `PugServerException` for Pug errors
- Cross-platform support (Linux/macOS with Unix sockets, Windows with process fallback)
- Comprehensive test suite with 12 passing tests
- Complete documentation and examples
- Support for all Pug.js features and options

### Features
- **Performance**: 10-50x faster than process-per-request after initial startup
- **Type Safety**: Uses `dart:io` File objects for file operations
- **Error Handling**: Detailed error messages with appropriate exception types
- **Resource Management**: Automatic server lifecycle management
- **No Port Conflicts**: Uses Unix domain sockets instead of network ports
- **Auto Setup**: Automatically installs Pug.js if needed 