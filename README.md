# pug_dart

Native Dart Pug renderer with a safe expression engine.

Version 2 is a Node-free native Dart rewrite of `pug_dart`: templates stay as
Pug, but rendering happens in Dart. Compatibility is tracked with committed
golden fixtures generated from pinned upstream `pug@3.0.4`.

If you need the original Node-backed behavior, pin `pug_dart` to the latest
compatible `1.x` release.

## Migrating From 1.x

`pug_dart` 2.0.0 is a breaking rewrite. The package no longer starts a
persistent Node.js process, installs npm dependencies at runtime, exposes the
old singleton lifecycle API, or evaluates arbitrary JavaScript inside
templates.

Most applications should migrate by:

- Replacing singleton calls with the top-level `render`, `renderFile`,
  `compile`, or `compileFile` APIs.
- Passing precomputed values through `locals`.
- Moving template-only JavaScript helpers into explicit Dart helpers or
  filters.
- Pinning `pug_dart: ^1.2.1` if the application needs the old Node-backed
  runtime or full JavaScript expression compatibility.

## Status

This is an early native implementation. It already supports:

- Pug-like API: `render`, `renderFile`, `compile`, `compileFile`
- Tags, shorthand ids/classes, attributes, boolean attributes, `&attributes`
- Escaped and unescaped interpolation
- `if`, `else if`, `else`, `unless`, `each`, guarded `while`
- `include`, `extends`, `block`, `append`, `prepend`
- Mixins with arguments, defaults, attributes, and block bodies
- Dot text blocks for `script.`/`style.` style content
- `pretty` output formatting for supported HTML trees
- Source-spanned parse/render diagnostics and wrapped file-loading diagnostics
- Custom filters and explicit Dart helpers

It intentionally does not evaluate arbitrary JavaScript. Unsupported JS-only
expressions fail with `UnsupportedFeatureException`; precompute those values in
Dart or expose an explicit helper.

## Compatibility Matrix

Compatibility is measured against upstream `pug@3.0.4` with committed golden
fixtures. The project targets Pug syntax and rendering behavior, while replacing
JavaScript evaluation with a safe Dart expression subset.

| Pug language feature | Status | Notes |
| --- | --- | --- |
| Tags | Supported | Includes nested tags, self-closing tags, void tags, implicit `div`, and block expansion such as `a: img`. |
| Attributes | Supported | Includes multiline attributes, quoted names, boolean attributes, class arrays/maps, style maps, unescaped attributes, and `&attributes`. |
| Attribute interpolation | Partially supported | Pug 3 removed legacy `#{}` attribute interpolation. Use expression attributes such as `href='/' + url`. ES template strings are out of scope. |
| Text | Supported | Includes inline text, piped text, dot text blocks, and text interpolation. |
| Comments | Supported | Includes buffered and unbuffered comments, including indented comment blocks. |
| Doctypes | Supported | Includes Pug's documented doctype shortcuts. |
| Buffered code | Supported subset | `=` and `!=` work with the safe expression evaluator. |
| Unbuffered code | Out of scope | JavaScript statements such as `- var`, `- for`, and mutation are intentionally rejected. |
| Conditionals | Supported | Includes `if`, `else if`, `else`, and `unless`. |
| Case | Supported | Includes `case`, `when`, and `default` for simple branch values. JavaScript fall-through semantics are not supported. |
| Iteration | Supported | Includes array/list iteration, map/object iteration, index/key variables, and `else` branches. |
| Includes | Supported | Pug files resolve relative to the current file; missing files throw `PugIOException`. Raw text includes and filtered includes are not implemented. |
| Inheritance | Supported | Includes `extends`, `block`, `append`, and `prepend`. |
| Mixins | Supported subset | Includes arguments, defaults, call attributes, nested calls, and block bodies. Rest args and advanced JavaScript argument expressions are out of scope. |
| Filters | Dart-native only | Custom Dart filters are supported through `PugOptions.filters`. JSTransformer filters are out of scope. |
| Interpolation | Supported subset | Escaped `#{...}` and unescaped `!{...}` work with safe expressions. |
| Pretty output | Supported | `PugOptions(pretty: true)` formats supported HTML output and is covered by upstream golden tests. |
| Caching | Basic | Parsed templates are cached by resolved path within a renderer instance. Dependency-aware invalidation is not implemented. |
| Browser compilation | Out of scope | This package is a Dart VM/server-side renderer. |

## Safe Expressions

The native evaluator supports literals, lists, maps, property and index lookup,
arithmetic, comparison, ternary expressions, JavaScript-like truthiness, `&&` and
`||` operand value semantics, and explicit Dart helpers.

Out of scope by design:

- Arbitrary JavaScript evaluation
- JavaScript statements and mutation
- Implicit globals such as `JSON`, `Math`, `Date`, and `moment`
- JavaScript methods such as `.toUpperCase()` except for the documented
  `toString()` case covered by the compatibility fixtures
- ES template strings
- JSTransformer filters such as `:markdown-it`, `:babel`, `:scss`, and
  filtered includes
- Raw text includes for non-Pug files
- Full Pug.js compile/runtime API compatibility beyond the Pug-like facade

## Usage

For Pug syntax, use the official language reference:
<https://pugjs.org/language/attributes.html>. This README focuses on how to
render Pug from Dart.

### Render an inline template

```dart
import 'package:pug_dart/pug_dart.dart' as pug;

final html = await pug.render('p Hello #{name}', {'name': 'Dart'});
```

### Render a file

```dart
import 'package:pug_dart/pug_dart.dart' as pug;

final html = await pug.renderFile('views/product.pug', {
  'product': {
    'name': 'Spiced Rum',
    'price': 6499,
    'inStock': true,
  },
});
```

Relative `include` and `extends` paths are resolved from the current template
file. Use `basedir` when your templates use project-root-relative paths.

```dart
final html = await pug.renderFile(
  'views/pages/home.pug',
  {'title': 'Home'},
  pug.PugOptions(basedir: 'views'),
);
```

### Reuse a compiled template

Use `compile` or `compileFile` when rendering the same template repeatedly with
different locals.

```dart
final template = pug.compileFile('views/product-card.pug');

final first = template.render({'name': 'Spiced Rum'});
final second = template.render({'name': 'White Rum'});
```

### Pass explicit Dart helpers

JavaScript globals and arbitrary JavaScript calls are intentionally unavailable.
Precompute values in Dart, or expose the small helper surface your templates
need.

```dart
final template = pug.compile('p= money(cents)', pug.PugOptions(
  helpers: {
    'money': (args) => '\$${((args.first as num) / 100).toStringAsFixed(2)}',
  },
));

final html = template.render({'cents': 1299});
```

### Register custom filters

Filters are Dart functions. This keeps the runtime Node-free and avoids pulling
in JSTransformer packages.

```dart
final html = await pug.render(
  '''
:upper
  rendered by a dart filter
''',
  const {},
  pug.PugOptions(
    filters: {
      'upper': (text, attrs) => text.toUpperCase(),
    },
  ),
);
```

### Pretty output

By default, output follows Pug's compact HTML style. Enable `pretty` when you
want formatted HTML.

```dart
final html = await pug.renderFile(
  'views/email.pug',
  {'name': 'Dart'},
  const pug.PugOptions(pretty: true),
);
```

### Custom loading

Provide a `PugTemplateLoader` when templates come from memory, a database, an
asset bundle, or another virtual filesystem.

```dart
class MapTemplateLoader implements pug.PugTemplateLoader {
  MapTemplateLoader(this.templates);

  final Map<String, String> templates;

  @override
  String resolve(String path, {String? from}) => path;

  @override
  String load(String path, {String? from}) {
    final source = templates[path];
    if (source == null) {
      throw pug.PugIOException('Missing template "$path"');
    }
    return source;
  }
}

final html = await pug.renderFile(
  'page.pug',
  {'title': 'Virtual templates'},
  pug.PugOptions(
    loader: MapTemplateLoader({
      'page.pug': 'include partial.pug\np= title',
      'partial.pug': 'h1 Loaded from memory',
    }),
  ),
);
```

## Golden Fixtures

Fixture cases live under `test/fixtures/<feature>/<case>/`:

- `template.pug`
- `locals.json`
- `options.json`
- `expected.html`

Regenerate expected HTML from pinned upstream Pug:

```sh
dart run tool/generate_goldens.dart
```

The generator installs `pug@3.0.4` through npm when needed. Normal Dart tests do
not require Node.

The `test/fixtures/docs/` tree mirrors examples from Pug's language reference.
Examples that require arbitrary JavaScript evaluation or JSTransformer packages
are covered by negative tests in `test/language_reference_unsupported_test.dart`
because this package intentionally requires precomputed Dart locals or explicit
Dart helpers/filters instead.

## CLI

```sh
dart run pug_dart:pug-dart render path/to/template.pug
dart run pug_dart:pug-dart compile-check path/to/template.pug
dart run pug_dart:pug-dart golden:update
```

## Quality Gates

```sh
dart format --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
dart test
dart pub publish --dry-run
```
