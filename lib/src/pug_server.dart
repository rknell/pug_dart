/// Server-side Dart wrapper for Pug.js using a persistent Node.js server.
///
/// This library provides a way to use Pug templates in server-side Dart
/// applications by communicating with a long-running Node.js server via Unix domain sockets.
library pug_server;

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'embedded_scripts.dart';

/// Server-side Pug wrapper that communicates with a persistent Node.js server.
class Pug {
  static String? _socketPath;
  static Process? _nodeProcess;
  static final Set<String> _tempScriptFiles = <String>{};
  static bool _isStarting = false;

  /// Sets up Pug.js by running npm install.
  ///
  /// This function will install Pug.js globally if it's not already installed.
  /// It checks for both local and global installations.
  ///
  /// Returns `true` if setup was successful, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// final success = await PugServer.setup();
  /// if (success) {
  ///   print('Pug.js is ready to use!');
  /// } else {
  ///   print('Failed to setup Pug.js');
  /// }
  /// ```
  static Future<bool> setup({bool verbose = false}) async {
    if (verbose) print('Checking if Pug.js is available...');

    // First check if Pug is already available
    if (await _isPugAvailable()) {
      if (verbose) print('✅ Pug.js is already installed and available.');
      return true;
    }

    if (verbose) print('Pug.js not found. Installing...');

    // Try to install Pug locally first
    if (await _installPugLocally(verbose)) {
      if (verbose) print('✅ Pug.js installed locally.');
      return true;
    }

    // If local install fails, try global install
    if (await _installPugGlobally(verbose)) {
      if (verbose) print('✅ Pug.js installed globally.');
      return true;
    }

    if (verbose) print('❌ Failed to install Pug.js.');
    return false;
  }

  /// Checks if Pug.js is available for use.
  ///
  /// Returns `true` if Pug can be used, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// if (await PugServer.isAvailable()) {
  ///   final html = await PugServer.render('p Hello World');
  /// } else {
  ///   await PugServer.setup();
  /// }
  /// ```
  static Future<bool> isAvailable() async {
    return await _isPugAvailable();
  }

  /// Starts the persistent Node.js server if not already running.
  static Future<void> _ensureServerRunning() async {
    if (Platform.isWindows) {
      // Windows uses fallback process-per-request approach, no server needed
      return;
    }

    if (_isStarting) {
      // Wait for the current startup to complete
      while (_isStarting) {
        await Future.delayed(Duration(milliseconds: 50));
      }
      return;
    }

    if (_nodeProcess != null && _socketPath != null) {
      // Check if server is still responsive
      try {
        await _sendRequest({'action': 'ping'});
        return; // Server is running and responsive
      } catch (e) {
        // Server is not responsive, restart it
        await _stopServer();
      }
    }

    _isStarting = true;
    try {
      await _startServer();
    } finally {
      _isStarting = false;
    }
  }

  /// Starts the Node.js server
  static Future<void> _startServer() async {
    // Generate a unique socket path
    final random = Random();
    final socketName = 'pug_server_${random.nextInt(999999)}.sock';
    _socketPath =
        Platform.isWindows ? '\\\\.\\pipe\\$socketName' : '/tmp/$socketName';

    // Get path to the server script
    final scriptPath = _getScriptPath('pug_server.js');

    // Start the Node.js server
    _nodeProcess = await Process.start('node', [scriptPath, _socketPath!]);

    // Wait for the server to output "ready"
    final readyCompleter = Completer<void>();
    _nodeProcess!.stdout.listen((data) {
      final output = String.fromCharCodes(data);
      if (output.contains('ready')) {
        readyCompleter.complete();
      }
    });

    _nodeProcess!.stderr.listen((data) {
      final error = String.fromCharCodes(data);
      if (error.trim().isNotEmpty) {
        print('Node.js server error: $error');
      }
    });

    try {
      await readyCompleter.future.timeout(Duration(seconds: 10));
    } catch (e) {
      await _stopServer();
      throw PugServerException('Failed to start Node.js server: $e');
    }

    // Test connection
    try {
      await _sendRequest({'action': 'ping'});
    } catch (e) {
      await _stopServer();
      throw PugServerException('Failed to connect to Node.js server: $e');
    }
  }

  /// Stops the Node.js server
  static Future<void> _stopServer() async {
    if (_nodeProcess != null) {
      _nodeProcess!.kill();
      await _nodeProcess!.exitCode;
      _nodeProcess = null;
    }

    if (_socketPath != null && !Platform.isWindows) {
      try {
        await File(_socketPath!).delete();
      } catch (e) {
        // Ignore errors when deleting socket file
      }
      _socketPath = null;
    }

    // Clean up temporary script files
    for (final tempFile in _tempScriptFiles) {
      try {
        await File(tempFile).delete();
      } catch (e) {
        // Ignore errors when deleting temp files
      }
    }
    _tempScriptFiles.clear();
  }

  /// Sends a request to the Node.js server and returns the response
  static Future<Map<String, dynamic>> _sendRequest(
      Map<String, dynamic> request) async {
    if (Platform.isWindows) {
      // Fallback to old process-per-request approach for Windows
      return await _sendRequestViaProcess(request);
    }

    if (_socketPath == null) {
      throw PugServerException('Server not running');
    }

    // Add unique ID to request
    final requestId = Random().nextInt(999999).toString();
    request['id'] = requestId;

    Socket? socket;
    try {
      // Connect to the Unix domain socket
      socket = await Socket.connect(
          InternetAddress(_socketPath!, type: InternetAddressType.unix), 0);

      final completer = Completer<Map<String, dynamic>>();
      String buffer = '';

      socket.listen(
        (data) {
          buffer += String.fromCharCodes(data);

          // Check for complete response (ends with newline)
          final lines = buffer.split('\n');
          for (final line in lines) {
            if (line.trim().isNotEmpty) {
              try {
                final response = jsonDecode(line) as Map<String, dynamic>;
                if (response['id'] == requestId) {
                  completer.complete(response);
                  return;
                }
              } catch (e) {
                // Invalid JSON, continue reading
              }
            }
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(PugServerException('Socket error: $error'));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
                PugServerException('Connection closed unexpectedly'));
          }
        },
      );

      // Send the request
      final requestStr = jsonEncode(request) + '\n';
      socket.write(requestStr);

      // Wait for response with timeout
      final response = await completer.future.timeout(
        Duration(seconds: 30),
        onTimeout: () => throw PugServerException('Request timeout'),
      );

      return response;
    } finally {
      socket?.destroy();
    }
  }

  /// Fallback method for Windows - uses the old process-per-request approach
  static Future<Map<String, dynamic>> _sendRequestViaProcess(
      Map<String, dynamic> request) async {
    final scriptPath = _getScriptPath('pug_fallback.js');
    final process = await Process.start('node', [scriptPath]);

    // Send the request as JSON to stdin
    process.stdin.writeln(jsonEncode(request));
    await process.stdin.close();

    // Read the response from stdout
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();

    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      throw PugServerException(
          'Node.js process failed with exit code $exitCode: $stderr');
    }

    try {
      final response = jsonDecode(stdout) as Map<String, dynamic>;
      return response;
    } catch (e) {
      throw PugServerException(
          'Failed to parse Node.js response: $e\nOutput: $stdout');
    }
  }

  /// Internal method to check if Pug is available
  static Future<bool> _isPugAvailable() async {
    try {
      final result = await Process.run(
          'node', ['-e', 'console.log(require("pug").render("p test"))']);
      return result.exitCode == 0 &&
          result.stdout.toString().contains('<p>test</p>');
    } catch (e) {
      return false;
    }
  }

  /// Internal method to install Pug locally
  static Future<bool> _installPugLocally(bool verbose) async {
    try {
      if (verbose) print('Running: npm install pug');
      final result = await Process.run('npm', ['install', 'pug']);

      if (verbose && result.stderr.toString().isNotEmpty) {
        print('npm stderr: ${result.stderr}');
      }

      return result.exitCode == 0;
    } catch (e) {
      if (verbose) print('Local install failed: $e');
      return false;
    }
  }

  /// Internal method to install Pug globally
  static Future<bool> _installPugGlobally(bool verbose) async {
    try {
      if (verbose) print('Running: npm install -g pug');
      final result = await Process.run('npm', ['install', '-g', 'pug']);

      if (verbose && result.stderr.toString().isNotEmpty) {
        print('npm stderr: ${result.stderr}');
      }

      return result.exitCode == 0;
    } catch (e) {
      if (verbose) print('Global install failed: $e');
      return false;
    }
  }

  /// Renders a Pug template string with optional data and options.
  ///
  /// [template] is the Pug template source code.
  /// [data] is a Map containing template variables (optional).
  /// [options] is a Map containing Pug options (optional).
  ///
  /// Returns the rendered HTML as a String.
  ///
  /// Throws [PugServerException] for Pug compilation/rendering errors.
  ///
  /// Example:
  /// ```dart
  /// final html = await PugServer.render(
  ///   'h1= title\np Welcome to #{name}!',
  ///   {'title': 'My Site', 'name': 'Dart'}
  /// );
  /// ```
  static Future<String> render(
    String template, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureServerRunning();

    final request = {
      'action': 'render',
      'template': template,
      'data': data,
      'options': options,
    };

    final response = await _sendRequest(request);

    if (response['success'] == true) {
      return response['result'] as String;
    } else {
      throw PugServerException('Pug render error: ${response['error']}');
    }
  }

  /// Renders a Pug template file with optional data and options.
  ///
  /// [file] is the File object pointing to the Pug template file.
  /// [data] is a Map containing template variables (optional).
  /// [options] is a Map containing Pug options (optional).
  ///
  /// Returns the rendered HTML as a String.
  ///
  /// Throws [FileSystemException] if the template file is not found.
  /// Throws [PugServerException] for Pug compilation/rendering errors.
  ///
  /// Example:
  /// ```dart
  /// final templateFile = File('templates/index.pug');
  /// final html = await PugServer.renderFile(
  ///   templateFile,
  ///   {'title': 'My Site', 'users': ['Alice', 'Bob']}
  /// );
  /// ```
  static Future<String> renderFile(
    File file, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureServerRunning();

    final request = {
      'action': 'renderFile',
      'filename': file.absolute.path,
      'data': data,
      'options': options,
    };

    final response = await _sendRequest(request);

    if (response['success'] == true) {
      return response['result'] as String;
    } else {
      _throwAppropriateException(response, file.path);
    }
  }

  /// Compiles and renders a Pug template string in one step.
  ///
  /// [template] is the Pug template source code.
  /// [data] is a Map containing template variables (optional).
  /// [options] is a Map containing Pug compilation options (optional).
  ///
  /// Returns the rendered HTML as a String.
  ///
  /// Throws [PugServerException] for Pug compilation/rendering errors.
  ///
  /// Example:
  /// ```dart
  /// final html = await PugServer.compile(
  ///   'h1= title\np= message',
  ///   {'title': 'Hello', 'message': 'World'}
  /// );
  /// ```
  static Future<String> compile(
    String template, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureServerRunning();

    final request = {
      'action': 'compile',
      'template': template,
      'data': data,
      'options': options,
    };

    final response = await _sendRequest(request);

    if (response['success'] == true) {
      return response['result'] as String;
    } else {
      throw PugServerException('Pug compile error: ${response['error']}');
    }
  }

  /// Compiles and renders a Pug template file in one step.
  ///
  /// [file] is the File object pointing to the Pug template file.
  /// [data] is a Map containing template variables (optional).
  /// [options] is a Map containing Pug compilation options (optional).
  ///
  /// Returns the rendered HTML as a String.
  ///
  /// Throws [FileSystemException] if the template file is not found.
  /// Throws [PugServerException] for Pug compilation/rendering errors.
  ///
  /// Example:
  /// ```dart
  /// final templateFile = File('templates/layout.pug');
  /// final html = await PugServer.compileFile(
  ///   templateFile,
  ///   {'title': 'My Page', 'content': 'Hello World'}
  /// );
  /// ```
  static Future<String> compileFile(
    File file, [
    Map<String, dynamic>? data,
    Map<String, dynamic>? options,
  ]) async {
    await _ensureServerRunning();

    final request = {
      'action': 'compileFile',
      'filename': file.absolute.path,
      'data': data,
      'options': options,
    };

    final response = await _sendRequest(request);

    if (response['success'] == true) {
      return response['result'] as String;
    } else {
      _throwAppropriateException(response, file.path);
    }
  }

  /// Throws the appropriate exception based on the error response
  static Never _throwAppropriateException(
      Map<String, dynamic> response, String? filePath) {
    final error = response['error'] as String;
    final errorType = response['errorType'] as String?;

    // Check for file not found errors
    if (error.contains('ENOENT') ||
        error.contains('no such file') ||
        error.contains('cannot resolve') ||
        errorType == 'ENOENT') {
      throw FileSystemException(
          'Template file not found', filePath, OSError(error));
    }

    // Check for permission errors
    if (error.contains('EACCES') || errorType == 'EACCES') {
      throw FileSystemException('Permission denied', filePath, OSError(error));
    }

    // Default to PugServerException
    throw PugServerException('Pug error: $error');
  }

  /// Stops the persistent Node.js server.
  ///
  /// Call this when you're done using PugServer to clean up resources.
  /// The server will be automatically restarted if needed on the next render call.
  ///
  /// Example:
  /// ```dart
  /// // When your app is shutting down
  /// await PugServer.shutdown();
  /// ```
  static Future<void> shutdown() async {
    await _stopServer();
  }

  /// Gets the absolute path to a script file by creating a temporary file from embedded content
  static String _getScriptPath(String scriptName) {
    final String scriptContent;

    switch (scriptName) {
      case 'pug_server.js':
        scriptContent = pugServerScript;
        break;
      case 'pug_fallback.js':
        scriptContent = pugFallbackScript;
        break;
      default:
        throw PugServerException('Unknown script: $scriptName');
    }

    try {
      // Create a temporary file in the current working directory
      // so it can access local node_modules
      final tempFile = File('.pug_dart_temp_$scriptName');

      // Write the embedded script content to the temporary file
      tempFile.writeAsStringSync(scriptContent);

      // Track the temporary file for cleanup
      _tempScriptFiles.add(tempFile.absolute.path);

      return tempFile.absolute.path;
    } catch (e) {
      throw PugServerException('Failed to create temporary script file: $e');
    }
  }
}

/// Exception thrown when Pug server operations fail.
class PugServerException implements Exception {
  final String message;

  const PugServerException(this.message);

  @override
  String toString() => 'PugServerException: $message';
}
