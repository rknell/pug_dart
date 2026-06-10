import 'dart:io';

import 'package:pug_dart/pug_dart.dart' as pug;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _usage();
    return;
  }

  switch (args.first) {
    case 'render':
      if (args.length < 2) {
        stderr.writeln('Missing template path.');
        exitCode = 64;
        return;
      }
      stdout.write(await pug.renderFile(args[1]));
    case 'compile-check':
      if (args.length < 2) {
        stderr.writeln('Missing template path.');
        exitCode = 64;
        return;
      }
      pug.compileFile(args[1]);
      stdout.writeln('ok');
    case 'golden:update':
      final result = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'tool/generate_goldens.dart'],
        mode: ProcessStartMode.inheritStdio,
      );
      exitCode = await result.exitCode;
    default:
      stderr.writeln('Unknown command: ${args.first}');
      _usage();
      exitCode = 64;
  }
}

void _usage() {
  stdout.writeln('''
Usage:
  pug-dart render <template.pug>
  pug-dart compile-check <template.pug>
  pug-dart golden:update
''');
}
