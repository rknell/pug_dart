import 'package:pug_dart/pug_dart.dart' as pug;
import 'package:test/test.dart';

void main() {
  group('language reference examples outside the native-safe contract', () {
    test('unbuffered JavaScript examples fail clearly', () {
      expect(
        () => pug.compile(
            '- var authenticated = true\nbody(class=authenticated ? "authed" : "anon")'),
        returnsNormally,
      );
      expect(
        () => pug.render(
            '- var authenticated = true\nbody(class=authenticated ? "authed" : "anon")'),
        throwsA(isA<pug.UnsupportedFeatureException>()),
      );
      expect(
        () => pug.compile('- for (var x = 0; x < 3; x++)\n  li item'),
        throwsA(isA<pug.UnsupportedFeatureException>()),
      );
    });

    test('implicit JavaScript globals and methods are not evaluated', () async {
      await expectLater(
        () => pug.render('p= JSON.stringify(value)', {'value': 'x'}),
        throwsA(isA<pug.UnsupportedFeatureException>()),
      );
      await expectLater(
        () => pug.render('p= msg.toUpperCase()', {'msg': 'quiet'}),
        throwsA(isA<pug.UnsupportedFeatureException>()),
      );
    });

    test('JSTransformer filters require explicit Dart filters', () async {
      await expectLater(
        () => pug.render(':markdown-it\n  # Markdown'),
        throwsA(isA<pug.UnsupportedFeatureException>()),
      );
    });
  });
}
