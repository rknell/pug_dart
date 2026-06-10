import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pug_dart/pug_dart.dart' as pug;
import 'package:test/test.dart';

void main() {
  group('golden parity fixtures', () {
    final fixtureRoot = Directory('test/fixtures');
    final cases = fixtureRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.basename(file.path) == 'template.pug')
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final template in cases) {
      final dir = p.dirname(template.path);
      test(p.relative(dir, from: fixtureRoot.path), () async {
        final locals = _readJson(File(p.join(dir, 'locals.json')));
        final options = _readJson(File(p.join(dir, 'options.json')));
        final expected = File(p.join(dir, 'expected.html')).readAsStringSync();
        final html = await pug.renderFile(
          template.path,
          locals,
          pug.PugOptions(
            filename: template.path,
            pretty: options['pretty'] == true,
            doctype: options['doctype'] as String?,
          ),
        );
        expect(_normalizeLineEndings(html), _normalizeLineEndings(expected));
      });
    }
  });
}

Map<String, Object?> _readJson(File file) {
  if (!file.existsSync()) return {};
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

String _normalizeLineEndings(String value) => value.replaceAll('\r\n', '\n');
