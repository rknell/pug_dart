/// A high-performance Dart wrapper for the Pug.js templating engine.
///
/// This library provides server-side Pug template rendering using a persistent
/// Node.js server with Unix domain sockets for fast inter-process communication.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:pug_dart/pug_dart.dart';
/// import 'dart:io';
///
/// void main() async {
///   // Auto-setup if needed
///   if (!await PugServer.isAvailable()) {
///     await PugServer.setup(verbose: true);
///   }
///
///   // Render a template
///   final html = await PugServer.render(
///     'h1= title\np Welcome to #{name}!',
///     {'title': 'My Site', 'name': 'Dart'}
///   );
///   print(html);
///
///   // Clean up
///   await PugServer.shutdown();
/// }
/// ```
///
/// ## Features
///
/// - High-performance persistent Node.js server
/// - Unix domain socket communication (no port conflicts)
/// - Type-safe File object support
/// - Automatic Pug.js installation
/// - Comprehensive error handling
/// - Cross-platform support (Linux, macOS, Windows fallback)
library pug_dart;

export 'pug_server.dart';
