## 2.0.0

- Rebuilt `pug_dart` as a native Dart Pug renderer.
- Removed the Node.js runtime dependency from normal rendering.
- Added Pug-like `render`, `renderFile`, `compile`, and `compileFile` APIs.
- Added parser, AST, safe evaluator, renderer, loaders, diagnostics, helpers,
  filters, mixins, includes, inheritance, and a golden parity harness.
- Added committed golden fixtures generated from pinned upstream `pug@3.0.4`.
- Added source-spanned parse/render diagnostics and wrapped file-loading
  diagnostics.
- Added `pretty` output support for supported HTML trees.

### Breaking changes

- Arbitrary JavaScript evaluation is no longer supported.
- JavaScript statements, mutation, implicit globals such as `JSON`, `Math`,
  `Date`, and `moment`, and JSTransformer filters are intentionally out of
  scope.
- Templates that depended on JavaScript-heavy expressions should precompute
  values in Dart or expose explicit Dart helpers and filters.
- The implementation is now a native Dart renderer rather than a wrapper around
  the original JavaScript Pug runtime.

If you need the original Node-backed behavior, pin `pug_dart` to the latest
compatible `1.x` release.
