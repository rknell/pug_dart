import 'ast.dart';
import 'options.dart';
import 'parser.dart';
import 'renderer.dart';

Future<String> render(
  String source, [
  Map<String, Object?> locals = const {},
  PugOptions? options,
]) async {
  return compile(source, options).render(locals);
}

Future<String> renderFile(
  String path, [
  Map<String, Object?> locals = const {},
  PugOptions? options,
]) async {
  return compileFile(path, options).render(locals);
}

CompiledPugTemplate compile(String source, [PugOptions? options]) {
  final effectiveOptions = options ?? const PugOptions();
  final filename = effectiveOptions.filename ?? 'inline.pug';
  final document = PugParser(source, filename: filename).parse();
  return CompiledPugTemplate(document, effectiveOptions);
}

CompiledPugTemplate compileFile(String path, [PugOptions? options]) {
  final effectiveOptions = options ?? const PugOptions();
  final resolved = effectiveOptions.effectiveLoader.resolve(path);
  final source = effectiveOptions.effectiveLoader.load(resolved);
  final document = PugParser(source, filename: resolved).parse();
  return CompiledPugTemplate(
      document, effectiveOptions.copyWith(filename: resolved));
}

class CompiledPugTemplate {
  const CompiledPugTemplate(this.document, this.options);

  final PugDocument document;
  final PugOptions options;

  String render([Map<String, Object?> locals = const {}]) {
    return PugRenderer(options).render(document, locals);
  }
}
