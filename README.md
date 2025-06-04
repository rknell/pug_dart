# Pug Dart

A Dart wrapper for the [Pug.js](https://pugjs.org/) templating engine for server-side applications.

## Features

- ✅ **Server-Side Rendering**: Use Pug templates in Dart backend applications
- ✅ **Full Pug Support**: Complete access to Pug.js functionality via Node.js processes
- ✅ **Type Safe**: Full type safety with proper Dart type annotations
- ✅ **Template Compilation**: Compile templates once, render multiple times
- ✅ **File Support**: Render templates directly from files
- ✅ **Options Support**: Full support for Pug compilation and rendering options
- ✅ **Async API**: Non-blocking operations with Future-based API
- ✅ **Auto Setup**: Automatic Pug.js installation via npm

## Requirements

- Dart SDK 3.3.0 or higher
- Node.js and npm installed
- **Server/Command-line environment**: This library uses `dart:io` Process to execute Node.js

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
  
  // Now you can use Pug templates
  final html = await PugServer.render('h1 Hello World');
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
  
  // Use Pug templates...
}
```

### Basic Template Rendering

```dart
import 'package:pug_dart/pug_server.dart';

void main() async {
  // Simple template rendering
  final html = await PugServer.render(
    'h1= title\np Welcome to #{name}!',
    {'title': 'My Site', 'name': 'Dart'}
  );
  print(html);
  // Output: <h1>My Site</h1><p>Welcome to Dart!</p>
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
  // Render template from file
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

The library will throw `PugServerException` if there are compilation, rendering, or Node.js execution errors:

```dart
try {
  final html = await PugServer.render('invalid[ pug syntax');
} catch (e) {
  if (e is PugServerException) {
    print('Pug error: ${e.message}');
  }
}
```

## Testing

Tests can be run normally since this library uses `dart:io` instead of web-specific APIs:

```bash
dart test
```

## Use Cases

This library is perfect for:
- Server-side web applications
- Static site generators
- Email template rendering
- Report generation
- Command-line tools that need HTML output

## Performance Notes

- Each render operation spawns a Node.js process, so for high-frequency rendering, consider caching
- Template compilation happens every time, but Pug's internal caching can be enabled with the `cache` option
- For maximum performance, pre-compile templates and reuse them

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 