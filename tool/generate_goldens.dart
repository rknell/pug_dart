import 'dart:io';

import 'package:path/path.dart' as p;

const pugVersion = '3.0.4';

Future<void> main(List<String> args) async {
  final root = Directory.current;
  final fixtures = Directory(p.join(root.path, 'test', 'fixtures'));
  if (!fixtures.existsSync()) {
    stderr.writeln('No test/fixtures directory found.');
    exitCode = 1;
    return;
  }

  if (!Directory(p.join(root.path, 'node_modules', 'pug')).existsSync()) {
    stderr
        .writeln('Installing pinned pug@$pugVersion for golden generation...');
    final install = await Process.run('npm', ['install']);
    stdout.write(install.stdout);
    stderr.write(install.stderr);
    if (install.exitCode != 0) {
      exitCode = install.exitCode;
      return;
    }
  }

  final cases = fixtures
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => p.basename(file.path) == 'template.pug')
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final template in cases) {
    final dir = p.dirname(template.path);
    final locals = File(p.join(dir, 'locals.json'));
    final options = File(p.join(dir, 'options.json'));
    final result = await Process.run('node', [
      p.join('tool', 'render_with_pug.js'),
      template.path,
      locals.path,
      options.path,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('Failed to render ${template.path}');
      stderr.write(result.stderr);
      exitCode = result.exitCode;
      return;
    }
    File(p.join(dir, 'expected.html'))
        .writeAsStringSync(result.stdout.toString());
    stdout.writeln('updated ${p.relative(dir)}/expected.html');
  }
}
