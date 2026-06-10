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

  test('node migration compatibility supports common safe JavaScript habits',
      () async {
    final html = await pug.render(
      '''
- const price = product.price || 0
a(href=`/products/\${product.slug}` data-json=JSON.stringify(product) data-tags=product.tags.join(', '))
  = Math.round(price / 100)
span= price.toFixed(2)
p= product.tags.includes('spiced') ? String(product.tags.length) : Number('0')
''',
      {
        'product': {
          'slug': 'spiced-rum',
          'price': 6499,
          'tags': ['spiced', 'rum'],
        },
      },
      const pug.PugOptions(
        compatibility: pug.PugCompatibility.nodeMigration,
      ),
    );
    expect(
      html,
      '<a href="/products/spiced-rum" data-json="{&quot;slug&quot;:&quot;spiced-rum&quot;,&quot;price&quot;:6499,&quot;tags&quot;:[&quot;spiced&quot;,&quot;rum&quot;]}" data-tags="spiced, rum">65</a><span>6499.00</span><p>2</p>',
    );
  });

  test('local assignments are opt-in with actionable diagnostics', () async {
    await expectLater(
      () => pug.render('- var sf = storefront\np= sf', {'storefront': 'main'}),
      throwsA(
        isA<pug.UnsupportedFeatureException>().having(
          (error) => error.message,
          'message',
          contains('Enable allowLocalAssignments'),
        ),
      ),
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
