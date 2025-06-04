# Pug Dart

A high-performance Dart wrapper for the [Pug.js](https://pugjs.org/) templating engine for server-side applications.

## Features

- ✅ **High Performance**: Uses a persistent Node.js server with Unix domain sockets for fast inter-process communication
- ✅ **Server-Side Rendering**: Use Pug templates in Dart backend applications
- ✅ **Full Pug Support**: Complete access to Pug.js functionality
- ✅ **Type Safe**: Full type safety with proper Dart type annotations
- ✅ **Template Compilation**: Compile templates once, render multiple times
- ✅ **File Support**: Render templates directly from files using `dart:io` File objects
- ✅ **Options Support**: Full support for Pug compilation and rendering options
- ✅ **Async API**: Non-blocking operations with Future-based API
- ✅ **Auto Setup**: Automatic Pug.js installation via npm
- ✅ **Resource Management**: Automatic server lifecycle management with graceful shutdown

## Architecture

This library uses a persistent Node.js server that communicates via Unix domain sockets (no port conflicts). The server starts automatically on first use and stays running for subsequent requests, providing much better performance than spawning a new process for each render operation.

## Requirements

- Dart SDK 3.0.0 or higher
- Node.js and npm installed
- **Unix-like system**: Currently supports Linux and macOS (Windows support coming soon)
- **Server/Command-line environment**: This library uses `dart:io` Process and Unix domain sockets

## Installation

1. Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  pug_dart: ^1.0.0
```

2. The library can automatically install Pug.js for you:

```dart
import 'package:pug_dart/pug_server.dart';

void main() async {
  // Check if Pug is available, install if needed
  if (!await PugServer.isAvailable()) {
    print('Installing Pug.js...');
    await PugServer.setup(verbose: true);
  }
  
  // Now you can use Pug templates - server starts automatically
  final html = await PugServer.render('h1 Hello World');
  
  // Clean up when done (optional, happens automatically on app exit)
  await PugServer.shutdown();
}
```

Or install manually:
```bash
npm install pug@^3.0.3
```

## Usage

### Setup and Availability Check

```dart
import 'package:pug_dart/pug_server.dart';

void main() async {
  // Check if Pug.js is available
  if (await PugServer.isAvailable()) {
    print('Pug.js is ready!');
  } else {
    // Automatically install Pug.js
    final success = await PugServer.setup(verbose: true);
    if (success) {
      print('Pug.js installed successfully!');
    } else {
      print('Failed to install Pug.js');
      return;
    }
  }
  
  // Use Pug templates - persistent server starts automatically
}
```

### Basic Template Rendering

```dart
import 'package:pug_dart/pug_server.dart';

void main() async {
  // Simple template rendering - server starts automatically on first call
  final html = await PugServer.render(
    'h1= title\np Welcome to #{name}!',
    {'title': 'My Site', 'name': 'Dart'}
  );
  print(html);
  // Output: <h1>My Site</h1><p>Welcome to Dart!</p>
  
  // Subsequent calls are much faster (same server, just socket communication)
  final html2 = await PugServer.render('p This is fast!');
}
```

### Template Compilation (for better performance)

```dart
import 'package:pug_dart/pug_server.dart';

void main() async {
  // Compile once, render multiple times
  final users = [
    {'name': 'Alice', 'email': 'alice@example.com', 'role': 'Admin'},
    {'name': 'Bob', 'email': 'bob@example.com', 'role': 'User'},
  ];
  
  for (final user in users) {
    final html = await PugServer.compile(
      '.user-card\n  h2= user.name\n  p Email: #{user.email}\n  p Role: #{user.role}',
      {'user': user}
    );
    print(html);
  }
}
```

### File-based Templates

```dart
import 'package:pug_dart/pug_server.dart';
import 'dart:io';

void main() async {
  // Render template from file using File objects
  final templateFile = File('templates/layout.pug');
  final html = await PugServer.renderFile(
    templateFile,
    {
      'title': 'My Website',
      'content': 'This is the main content',
      'user': {'name': 'John', 'email': 'john@example.com'}
    },
    {'pretty': true, 'cache': true}
  );
  print(html);
}
```

### Advanced Options

```dart
import 'package:pug_dart/pug_server.dart';

void main() async {
  // Using compilation options
  final html = await PugServer.render(
    'doctype html\nhtml\n  body\n    h1 Hello #{name}',
    {'name': 'World'},
    {
      'pretty': true,          // Pretty print output
      'cache': true,           // Cache compiled templates
      'compileDebug': false,   // Disable debug info
      'filename': 'template.pug' // For error reporting
    }
  );
  print(html);
}
```

### Resource Management

```dart
import 'package:pug_dart/pug_server.dart';

void main() async {
  // Server starts automatically on first render
  await PugServer.render('h1 Hello World');
  
  // Do lots of rendering - all use the same persistent server
  for (int i = 0; i < 1000; i++) {
    await PugServer.render('p Item #{i}', {'i': i});
  }
  
  // Gracefully shut down the server when done (optional)
  await PugServer.shutdown();
  
  // Server will restart automatically if you render again
  await PugServer.render('p Server restarted');
}
```

## API Reference

### PugServer Class

The main interface for server-side Pug functionality:

#### Static Methods

- `Future<bool> setup({bool verbose = false})` - Install Pug.js via npm if not available
- `Future<bool> isAvailable()` - Check if Pug.js is available for use
- `Future<String> render(String template, [Map<String, dynamic>? data, Map<String, dynamic>? options])` - Compile and render a template string
- `Future<String> renderFile(File file, [Map<String, dynamic>? data, Map<String, dynamic>? options])` - Compile and render a template file  
- `Future<String> compile(String template, [Map<String, dynamic>? data, Map<String, dynamic>? options])` - Compile and render a template string in one step
- `Future<String> compileFile(File file, [Map<String, dynamic>? data, Map<String, dynamic>? options])` - Compile and render a template file in one step
- `Future<void> shutdown()` - Gracefully shut down the persistent Node.js server

### Exception Handling

- `PugServerException` - Thrown when Pug operations fail

## Common Options

| Option | Type | Description |
|--------|------|-------------|
| `filename` | String | Template filename (for error reporting) |
| `pretty` | bool | Add pretty-printing whitespace |
| `cache` | bool | Cache compiled templates |
| `compileDebug` | bool | Include debugging information |
| `doctype` | String | Doctype to use |

## Error Handling

The library provides detailed error handling with appropriate exception types:

### File-related Errors

For file-based operations (`renderFile`, `compileFile`), the library throws:

- `FileSystemException` - When template files are not found or inaccessible
- `PugServerException` - For Pug compilation/rendering errors

```dart
try {
  final templateFile = File('templates/nonexistent.pug');
  final html = await PugServer.renderFile(templateFile);
} catch (e) {
  if (e is FileSystemException) {
    print('File error: ${e.message}');
    print('Path: ${e.path}');
  } else if (e is PugServerException) {
    print('Pug error: ${e.message}');
  }
}
```

### Template Errors

For template compilation/rendering errors:

```dart
try {
  final html = await PugServer.render('invalid[ pug syntax');
} catch (e) {
  if (e is PugServerException) {
    print('Pug error: ${e.message}');
    // Will show detailed Pug syntax error with line numbers
  }
}
```

### Server Communication Errors

For server-related issues:

```dart
try {
  final html = await PugServer.render('h1 Hello World');
} catch (e) {
  if (e is PugServerException) {
    print('Server communication error: ${e.message}');
  }
}
```

## Testing

Tests can be run normally since this library uses `dart:io` instead of web-specific APIs:

```bash
dart test
```

## Performance

This library is designed for high performance:

- **Persistent Server**: One Node.js process stays running, eliminating startup overhead
- **Unix Domain Sockets**: Fast inter-process communication without network overhead
- **Automatic Management**: Server starts/stops automatically as needed
- **Connection Pooling**: Each request uses a new socket connection for thread safety

Typical performance improvements over process-per-request:
- **First call**: Similar (server startup overhead)
- **Subsequent calls**: 10-50x faster (no process spawning)
- **Memory usage**: Much lower (one persistent process vs many)

## Use Cases

This library is perfect for:
- Server-side web applications (Shelf, Angel, etc.)
- Static site generators
- Email template rendering
- Report generation  
- Command-line tools that need HTML output
- High-throughput template rendering

## Platform Support

Currently supported:
- ✅ Linux (all distributions)
- ✅ macOS
- ❌ Windows (coming soon - will use named pipes)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 