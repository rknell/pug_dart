# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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