/// A high-performance Dart wrapper for the Pug.js templating engine.
///
/// This library provides server-side Pug template rendering using a persistent
/// Node.js server with Unix domain sockets for fast inter-process communication.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:pug_dart/pug_dart.dart';
///
/// main() async {
///   var html = await pug.render('h1 Hello World');
///   print('Rendered HTML: $html');
///   await pug.dispose();
/// }
/// ```
///
/// ## Features
///
/// - High-performance persistent Node.js server
/// - Unix domain socket communication (no port conflicts)
/// - Type-safe File object support
/// - Automatic Pug.js installation
/// - Singleton pattern with automatic initialization
/// - Comprehensive error handling
/// - Cross-platform support (Linux, macOS, Windows fallback)
library pug_dart;

import 'dart:io';
import 'src/pug_server.dart';

/// Export only the exception class for error handling
export 'src/pug_server.dart' show PugServerException;
export 'src/embedded_scripts.dart';

/// Singleton wrapper for Pug that automatically handles setup
class PugInstance {
  static PugInstance? _instance;
  bool _isInitialized = false;

  PugInstance._();

  /// Get the singleton instance
  static PugInstance get instance {
    _instance ??= PugInstance._();
    return _instance!;
  }

  /// Ensure Pug is set up and ready
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    if (!await Pug.isAvailable()) {
      final success = await Pug.setup(verbose: true);
      if (!success) {
        throw PugServerException('Failed to setup Pug.js automatically. '
            'Please check the verbose output above for detailed error information. '
            'Common issues include:\n'
            '• Node.js not installed or not in PATH\n'
            '• npm not available or network connectivity issues\n'
            '• Insufficient permissions to install packages\n'
            '• Firewall blocking npm access\n'
            '\nTo resolve this, try:\n'
            '1. Ensure Node.js and npm are installed: node --version && npm --version\n'
            '2. Try manual installation: npm install pug\n'
            '3. Check npm configuration: npm config list\n'
            '4. Verify network access: npm ping');
      }
    }

    _isInitialized = true;
  }

  /// Renders a Pug template string with optional data and options.
  /// Automatically sets up Pug.js on first call.
  Future<String> render(
    String template, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureInitialized();
    return await Pug.render(template, data, options);
  }

  /// Renders a Pug template file with optional data and options.
  /// Automatically sets up Pug.js on first call.
  Future<String> renderFile(
    File file, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureInitialized();
    return await Pug.renderFile(file, data, options);
  }

  /// Compiles and renders a Pug template string in one step.
  /// Automatically sets up Pug.js on first call.
  Future<String> compile(
    String template, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureInitialized();
    return await Pug.compile(template, data, options);
  }

  /// Compiles and renders a Pug template file in one step.
  /// Automatically sets up Pug.js on first call.
  Future<String> compileFile(
    File file, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureInitialized();
    return await Pug.compileFile(file, data, options);
  }

  /// Disposes resources and shuts down the Pug server.
  /// Call this when you're done using Pug to clean up resources.
  Future<void> dispose() async {
    await Pug.shutdown();
    _isInitialized = false;
  }
}

/// Global pug instance for convenient access
final pug = PugInstance.instance;
