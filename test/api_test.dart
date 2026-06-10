import 'dart:io';

import 'package:pug_dart/pug_dart.dart' as pug;
import 'package:test/test.dart';

void main() {
  test('compiled templates can be reused with different locals', () {
    final template = pug.compile('p Hello #{name}');
    expect(template.render({'name': 'Ada'}), '<p>Hello Ada</p>');
    expect(template.render({'name': 'Grace'}), '<p>Hello Grace</p>');
  });

  test('helpers are explicit and callable from safe expressions', () async {
    final html = await pug.render(
      'p= money(cents)',
      {'cents': 1234},
      pug.PugOptions(helpers: {
        'money': (args) =>
            '\$${((args.first as num) / 100).toStringAsFixed(2)}',
      }),
    );
    expect(html, '<p>\$12.34</p>');
  });

  test('unsupported JavaScript expressions fail clearly', () async {
    expect(
      () => pug.render('p= JSON.stringify(value)', {'value': 'x'}),
      throwsA(isA<pug.UnsupportedFeatureException>()),
    );
  });

  test('custom filters are explicit extension points', () async {
    final html = await pug.render(
      ':upper\n  hello',
      const {},
      pug.PugOptions(filters: {
        'upper': (text, attrs) => text.toUpperCase(),
      }),
    );
    expect(html, 'HELLO');
  });

  test('missing includes include filename and line in diagnostics', () async {
    final dir = Directory.systemTemp.createTempSync('pug_dart_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/page.pug')
      ..writeAsStringSync('include missing');
    expect(
      () => pug.renderFile(file.path),
      throwsA(
        isA<pug.PugIOException>()
            .having((error) => error.span?.filename, 'filename', file.path)
            .having((error) => error.span?.line, 'line', 1)
            .having((error) => error.message, 'message', contains('missing')),
      ),
    );
  });
}
