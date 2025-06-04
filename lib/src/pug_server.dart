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
  static String? _pidFilePath;
  static final Set<String> _tempScriptFiles = <String>{};
  static bool _isStarting = false;
  static bool _shutdownHookRegistered = false;
  static Timer? _healthCheckTimer;
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const String _pidFilePrefix = '.pug_dart_server_';

  /// Registers shutdown hooks and cleanup mechanisms for automatic resource management
  static void _registerShutdownHooks() {
    if (_shutdownHookRegistered) return;
    _shutdownHookRegistered = true;

    // Register process exit handler
    ProcessSignal.sigint.watch().listen((_) async {
      await _emergencyCleanup();
      exit(0);
    });

    ProcessSignal.sigterm.watch().listen((_) async {
      await _emergencyCleanup();
      exit(0);
    });

    // Schedule orphan cleanup for after server starts
    Timer(Duration(seconds: 5), () => _cleanupOrphanedResources());
  }

  /// Emergency cleanup for unexpected shutdowns
  static Future<void> _emergencyCleanup() async {
    _healthCheckTimer?.cancel();
    await _stopServer();
    await _cleanupPidFiles();
  }

  /// Cleans up orphaned processes and temporary files from previous runs
  static Future<void> _cleanupOrphanedResources() async {
    try {
      final directory = Directory('.');
      final pidFiles = await directory
          .list()
          .where((entity) =>
              entity is File && entity.path.contains(_pidFilePrefix))
          .cast<File>()
          .toList();

      for (final pidFile in pidFiles) {
        await _cleanupPidFile(pidFile);
      }

      // Clean up orphaned socket files
      if (!Platform.isWindows) {
        final tempDir = Directory('/tmp');
        if (await tempDir.exists()) {
          final socketFiles = await tempDir
              .list()
              .where((entity) =>
                  entity is File &&
                  entity.path.contains('pug_server_') &&
                  entity.path.endsWith('.sock'))
              .cast<File>()
              .toList();

          for (final socketFile in socketFiles) {
            try {
              await socketFile.delete();
            } catch (e) {
              // Ignore cleanup errors
            }
          }
        }
      }

      // Clean up OLD orphaned script files (older than 1 hour)
      final scriptFiles = await directory
          .list()
          .where((entity) =>
              entity is File && entity.path.contains('.pug_dart_temp_'))
          .cast<File>()
          .toList();

      for (final scriptFile in scriptFiles) {
        try {
          final stat = await scriptFile.stat();
          final age = DateTime.now().difference(stat.modified);

          // Only clean up files older than 1 hour
          if (age.inHours >= 1) {
            await scriptFile.delete();
          }
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    } catch (e) {
      // Ignore cleanup errors during startup
    }
  }

  /// Cleans up a specific PID file and associated process
  static Future<void> _cleanupPidFile(File pidFile) async {
    try {
      final pidStr = await pidFile.readAsString();
      final pid = int.tryParse(pidStr.trim());

      if (pid != null) {
        // Check if process is still running and kill it if it's a pug server
        if (await _isProcessRunning(pid)) {
          await _killProcessSafely(pid);
        }
      }

      await pidFile.delete();
    } catch (e) {
      // Ignore individual cleanup errors
    }
  }

  /// Safely checks if a process is running
  static Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'PID eq $pid']);
        return result.stdout.toString().contains('$pid');
      } else {
        final result = await Process.run('kill', ['-0', '$pid']);
        return result.exitCode == 0;
      }
    } catch (e) {
      return false;
    }
  }

  /// Safely kills a process
  static Future<void> _killProcessSafely(int pid) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/PID', '$pid']);
      } else {
        // Try graceful shutdown first
        await Process.run('kill', ['-TERM', '$pid']);
        await Future.delayed(Duration(seconds: 2));

        // Force kill if still running
        if (await _isProcessRunning(pid)) {
          await Process.run('kill', ['-KILL', '$pid']);
        }
      }
    } catch (e) {
      // Ignore kill errors
    }
  }

  /// Creates and manages a PID file for the server process
  static Future<void> _createPidFile(int pid) async {
    try {
      final random = Random();
      _pidFilePath = '$_pidFilePrefix${random.nextInt(999999)}.pid';
      final pidFile = File(_pidFilePath!);
      await pidFile.writeAsString(pid.toString());
    } catch (e) {
      // PID file creation is not critical
    }
  }

  /// Cleans up all PID files
  static Future<void> _cleanupPidFiles() async {
    if (_pidFilePath != null) {
      try {
        await File(_pidFilePath!).delete();
      } catch (e) {
        // Ignore cleanup errors
      }
      _pidFilePath = null;
    }
  }

  /// Starts health monitoring for the server process
  static void _startHealthMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) async {
      if (_nodeProcess != null) {
        try {
          await _sendRequest({'action': 'ping'});
        } catch (e) {
          // Server is not responsive, restart it
          await _restartServer();
        }
      }
    });
  }

  /// Restarts the server after a failure
  static Future<void> _restartServer() async {
    await _stopServer();
    await _startServer();
  }

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
    _registerShutdownHooks(); // Ensure cleanup hooks are registered

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
      _startHealthMonitoring();
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

    // Create PID file for cleanup
    await _createPidFile(_nodeProcess!.pid);

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
    _healthCheckTimer?.cancel();

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

    await _cleanupPidFiles();

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

    try {
      final socket = await Socket.connect(
          InternetAddress(_socketPath!, type: InternetAddressType.unix), 0);

      final requestJson = jsonEncode(request) + '\n';
      socket.write(requestJson);

      final responseCompleter = Completer<Map<String, dynamic>>();
      String buffer = '';

      socket.listen(
        (data) {
          buffer += String.fromCharCodes(data);
          final lines = buffer.split('\n');

          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isNotEmpty) {
              try {
                final response = jsonDecode(line) as Map<String, dynamic>;
                if (response['id'] == requestId) {
                  responseCompleter.complete(response);
                  break;
                }
              } catch (e) {
                // Invalid JSON, continue waiting
              }
            }
          }
          buffer = lines.last;
        },
        onError: (error) {
          if (!responseCompleter.isCompleted) {
            responseCompleter.completeError(
                PugServerException('Socket communication error: $error'));
          }
        },
        onDone: () {
          if (!responseCompleter.isCompleted) {
            responseCompleter.completeError(
                PugServerException('Socket closed unexpectedly'));
          }
        },
      );

      final response =
          await responseCompleter.future.timeout(Duration(seconds: 30));

      await socket.close();
      return response;
    } catch (e) {
      if (e is SocketException || e is TimeoutException) {
        // Server might be down, try to restart
        await _restartServer();
      }
      rethrow;
    }
  }

  /// Fallback method using process-per-request for Windows or when socket fails
  static Future<Map<String, dynamic>> _sendRequestViaProcess(
      Map<String, dynamic> request) async {
    final scriptPath = _getScriptPath('pug_fallback.js');

    final process = await Process.start('node', [scriptPath]);

    // Send request as JSON
    process.stdin.write(jsonEncode(request));
    await process.stdin.close();

    // Read response
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      throw PugServerException(
          'Node.js process failed with exit code $exitCode: $stderr');
    }

    try {
      return jsonDecode(stdout) as Map<String, dynamic>;
    } catch (e) {
      throw PugServerException('Invalid JSON response: $stdout');
    }
  }

  /// Checks if Pug.js is available by trying to run it
  static Future<bool> _isPugAvailable() async {
    try {
      final result = await Process.run('node', ['-e', 'require("pug")']);
      return result.exitCode == 0 &&
          !result.stderr.toString().contains('Cannot find module');
    } catch (e) {
      return false;
    }
  }

  /// Installs Pug.js locally
  static Future<bool> _installPugLocally(bool verbose) async {
    try {
      if (verbose) print('Installing Pug.js locally...');
      final result = await Process.run('npm', ['install', 'pug']);
      return result.exitCode == 0;
    } catch (e) {
      if (verbose) print('Local install failed: $e');
      return false;
    }
  }

  /// Installs Pug.js globally
  static Future<bool> _installPugGlobally(bool verbose) async {
    try {
      if (verbose) print('Installing Pug.js globally...');
      final result = await Process.run('npm', ['install', '-g', 'pug']);
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
  /// [options] is a Map containing Pug rendering options (optional).
  ///
  /// Returns the rendered HTML as a String.
  ///
  /// Throws [PugServerException] for Pug compilation/rendering errors.
  ///
  /// Example:
  /// ```dart
  /// final html = await PugServer.render(
  ///   'h1= title\np= message',
  ///   {'title': 'Hello', 'message': 'World'}
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
  /// [options] is a Map containing Pug rendering options (optional).
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
