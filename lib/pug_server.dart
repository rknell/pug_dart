/// Server-side Dart wrapper for Pug.js using Node.js processes.
///
/// This library provides a way to use Pug templates in server-side Dart
/// applications by executing Node.js scripts.
library pug_server;

import 'dart:convert';
import 'dart:io';

/// Server-side Pug wrapper that executes Node.js to render templates.
class PugServer {
  static const String _nodeScript = '''
const pug = require('pug');
const fs = require('fs');

// Read input from stdin
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  input += chunk;
});

process.stdin.on('end', () => {
  try {
    const request = JSON.parse(input);
    let result;
    
    switch (request.action) {
      case 'render':
        result = pug.render(request.template, request.data, request.options);
        break;
      case 'renderFile':
        result = pug.renderFile(request.filename, request.data, request.options);
        break;
      case 'compile':
        const compiled = pug.compile(request.template, request.options);
        result = compiled(request.data || {});
        break;
      case 'compileFile':
        const compiledFile = pug.compileFile(request.filename, request.options);
        result = compiledFile(request.data || {});
        break;
      default:
        throw new Error('Unknown action: ' + request.action);
    }
    
    console.log(JSON.stringify({ success: true, result: result }));
  } catch (error) {
    console.log(JSON.stringify({ success: false, error: error.message }));
  }
});
''';

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
    final request = {
      'action': 'render',
      'template': template,
      'data': data,
      'options': options,
    };

    return await _executeNodeScript(request);
  }

  /// Renders a Pug template file with optional data and options.
  ///
  /// [file] is the File object pointing to the Pug template file.
  /// [data] is a Map containing template variables (optional).
  /// [options] is a Map containing Pug options (optional).
  ///
  /// Returns the rendered HTML as a String.
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
    final request = {
      'action': 'renderFile',
      'filename': file.absolute.path,
      'data': data,
      'options': options,
    };

    return await _executeNodeScript(request);
  }

  /// Compiles and renders a Pug template string in one step.
  ///
  /// [template] is the Pug template source code.
  /// [data] is a Map containing template variables (optional).
  /// [options] is a Map containing Pug compilation options (optional).
  ///
  /// Returns the rendered HTML as a String.
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
    final request = {
      'action': 'compile',
      'template': template,
      'data': data,
      'options': options,
    };

    return await _executeNodeScript(request);
  }

  /// Compiles and renders a Pug template file in one step.
  ///
  /// [file] is the File object pointing to the Pug template file.
  /// [data] is a Map containing template variables (optional).
  /// [options] is a Map containing Pug compilation options (optional).
  ///
  /// Returns the rendered HTML as a String.
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
    final request = {
      'action': 'compileFile',
      'filename': file.absolute.path,
      'data': data,
      'options': options,
    };

    return await _executeNodeScript(request);
  }

  /// Executes the Node.js script with the given request.
  static Future<String> _executeNodeScript(Map<String, dynamic> request) async {
    final process = await Process.start('node', ['-e', _nodeScript]);

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

      if (response['success'] == true) {
        return response['result'] as String;
      } else {
        throw PugServerException('Pug error: ${response['error']}');
      }
    } catch (e) {
      throw PugServerException(
          'Failed to parse Node.js response: $e\nOutput: $stdout');
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
