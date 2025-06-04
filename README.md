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
- ✅ **Auto Setup**: Automatic Pug.js installation and initialization via npm
- ✅ **Singleton Pattern**: Global `pug` instance with automatic setup on first use
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

2. **⚠️ IMPORTANT: Node.js and npm must be installed on your system**

This library requires Node.js and npm to be available in your system PATH. Install them from [nodejs.org](https://nodejs.org/) before using this package.

3. The library automatically installs and sets up Pug.js on first use - no manual setup required!

## Quick Start

```dart
import 'package:pug_dart/pug_dart.dart';

main() async {
  var html = await pug.render('h1 Hello World');
  print('Rendered HTML: $html');
  await pug.dispose();
}
```

That's it! Just 3 lines and you're rendering Pug templates. Setup happens automatically.

## Usage

### Basic Template Rendering

```dart
import 'package:pug_dart/pug_dart.dart';

void main() async {
  // Simple template rendering - automatic setup on first call
  final html = await pug.render(
    'h1= title\np Welcome to #{name}!',
    {'title': 'My Site', 'name': 'Dart'}
  );
  print(html);
  // Output: <h1>My Site</h1><p>Welcome to Dart!</p>
  
  // Subsequent calls are much faster (same server, just socket communication)
  final html2 = await pug.render('p This is fast!');
  
  // Clean up when done
  await pug.dispose();
}
```

### Template Compilation (for better performance)

```dart
import 'package:pug_dart/pug_dart.dart';

void main() async {
  // Compile once, render multiple times
  final users = [
    {'name': 'Alice', 'email': 'alice@example.com', 'role': 'Admin'},
    {'name': 'Bob', 'email': 'bob@example.com', 'role': 'User'},
  ];
  
  for (final user in users) {
    final html = await pug.compile(
      '.user-card\n  h2= user.name\n  p Email: #{user.email}\n  p Role: #{user.role}',
      {'user': user}
    );
    print(html);
  }
  
  await pug.dispose();
}
```

### File-based Templates

```dart
import 'package:pug_dart/pug_dart.dart';
import 'dart:io';

void main() async {
  // Render template from file using File objects
  final templateFile = File('templates/layout.pug');
  final html = await pug.renderFile(
    templateFile,
    {
      'title': 'My Website',
      'content': 'This is the main content',
      'user': {'name': 'John', 'email': 'john@example.com'}
    },
    {'pretty': true, 'cache': true}
  );
  print(html);
  
  await pug.dispose();
}
```

### Advanced Options

```dart
import 'package:pug_dart/pug_dart.dart';

void main() async {
  // Using compilation options
  final html = await pug.render(
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
  
  await pug.dispose();
}
```

### Resource Management

```dart
import 'package:pug_dart/pug_dart.dart';

void main() async {
  // Server starts automatically on first render
  await pug.render('h1 Hello World');
  
  // Do lots of rendering - all use the same persistent server
  for (int i = 0; i < 1000; i++) {
    await pug.render('p Item #{i}', {'i': i});
  }
  
  // Gracefully shut down the server when done
  await pug.dispose();
  
  // Server will restart automatically if you render again
  await pug.render('p Server restarted');
  await pug.dispose();
}
```

### Auto-Cleanup and Crash Recovery

PugDart includes comprehensive auto-cleanup mechanisms to handle crashes, improper disposal, and orphaned processes:

#### Built-in Safety Features

- **Signal Handlers**: Automatically registers SIGINT and SIGTERM handlers for graceful shutdown
- **Process Monitoring**: Health checks monitor server responsiveness and restart failed servers
- **PID File Management**: Tracks server processes with PID files for cleanup after crashes
- **Orphan Detection**: Automatically detects and cleans up orphaned resources on startup
- **Resource Tracking**: Tracks all temporary files and sockets for comprehensive cleanup

#### Automatic Error Recovery

PugDart automatically handles various failure scenarios without any manual intervention:

```dart
import 'package:pug_dart/pug_dart.dart';

void main() async {
  // If the server crashes during rendering, it will automatically restart
  for (int i = 0; i < 100; i++) {
    try {
      await pug.render('p Rendering #{i}', {'i': i});
    } catch (e) {
      print('Render failed, but will retry: $e');
      // The next render call will automatically restart the server
    }
  }
  
  await pug.dispose();
}
```

#### Proper Resource Management

Always use proper resource management to ensure cleanup:

```dart
import 'package:pug_dart/pug_dart.dart';

void main() async {
  try {
    // Your application code
    await pug.render('h1 Hello World');
  } catch (e) {
    // Handle errors
    print('Error: $e');
  } finally {
    // Ensure cleanup happens even if something goes wrong
    await pug.dispose();
  }
}
```

## API Reference

The main interface is the `pug` singleton instance that automatically handles setup:

```dart
// Automatic setup on first use
final html = await pug.render(template, data, options);
final html2 = await pug.renderFile(file, data, options);
final html3 = await pug.compile(template, data, options);
final html4 = await pug.compileFile(file, data, options);

// Clean up
await pug.dispose();
```

### Methods

#### `render(template, [data], [options])` → `Future<String>`

Renders a Pug template string with optional data and options. Automatically sets up Pug.js on first call.

- `template` (String): The Pug template source code
- `data` (Map<String, dynamic>?, optional): Template variables
- `options` (Map<String, dynamic>?, optional): Pug compilation options

#### `renderFile(file, [data], [options])` → `Future<String>`

Renders a Pug template file with optional data and options. Automatically sets up Pug.js on first call.

- `file` (File): The File object pointing to the Pug template
- `data` (Map<String, dynamic>?, optional): Template variables  
- `options` (Map<String, dynamic>?, optional): Pug compilation options

#### `compile(template, [data], [options])` → `Future<String>`

Compiles and renders a Pug template string in one step. Automatically sets up Pug.js on first call.

- `template` (String): The Pug template source code
- `data` (Map<String, dynamic>?, optional): Template variables
- `options` (Map<String, dynamic>?, optional): Pug compilation options

#### `compileFile(file, [data], [options])` → `Future<String>`

Compiles and renders a Pug template file in one step. Automatically sets up Pug.js on first call.

- `file` (File): The File object pointing to the Pug template
- `data` (Map<String, dynamic>?, optional): Template variables
- `options` (Map<String, dynamic>?, optional): Pug compilation options

#### `dispose()` → `Future<void>`

Disposes resources and shuts down the Pug server. Call this when you're done using Pug to clean up resources.

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
  final html = await pug.renderFile(templateFile);
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
  final html = await pug.render('invalid[ pug syntax');
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
  final html = await pug.render('h1 Hello World');
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