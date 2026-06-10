import 'dart:io';

import 'package:path/path.dart' as p;

import 'diagnostics.dart';

typedef PugHelper = Object? Function(List<Object?> args);
typedef PugFilter = String Function(String text, Map<String, Object?> attrs);

abstract interface class PugTemplateLoader {
  String load(String path, {String? from});
  String resolve(String path, {String? from});
}

class FileSystemPugTemplateLoader implements PugTemplateLoader {
  FileSystemPugTemplateLoader({this.basedir});

  final String? basedir;

  @override
  String load(String path, {String? from}) {
    final resolved = resolve(path, from: from);
    try {
      return File(resolved).readAsStringSync();
    } on FileSystemException catch (error) {
      throw PugIOException(
        'Unable to load Pug template "$resolved": ${error.osError?.message ?? error.message}',
      );
    }
  }

  @override
  String resolve(String path, {String? from}) {
    var candidate = path;
    if (p.isRelative(candidate)) {
      final base =
          from == null ? (basedir ?? Directory.current.path) : p.dirname(from);
      candidate = p.normalize(p.join(base, candidate));
    }
    if (!p.extension(candidate).contains('pug')) {
      final withPug = '$candidate.pug';
      if (File(withPug).existsSync()) {
        return p.normalize(withPug);
      }
    }
    return p.normalize(candidate);
  }
}

class PugOptions {
  const PugOptions({
    this.filename,
    this.basedir,
    this.pretty = false,
    this.doctype,
    this.helpers = const {},
    this.filters = const {},
    this.loader,
    this.cache = true,
    this.maxWhileIterations = 10000,
  });

  final String? filename;
  final String? basedir;
  final bool pretty;
  final String? doctype;
  final Map<String, PugHelper> helpers;
  final Map<String, PugFilter> filters;
  final PugTemplateLoader? loader;
  final bool cache;
  final int maxWhileIterations;

  PugTemplateLoader get effectiveLoader =>
      loader ?? FileSystemPugTemplateLoader(basedir: basedir);

  PugOptions copyWith({
    String? filename,
    String? basedir,
    bool? pretty,
    String? doctype,
    Map<String, PugHelper>? helpers,
    Map<String, PugFilter>? filters,
    PugTemplateLoader? loader,
    bool? cache,
    int? maxWhileIterations,
  }) {
    return PugOptions(
      filename: filename ?? this.filename,
      basedir: basedir ?? this.basedir,
      pretty: pretty ?? this.pretty,
      doctype: doctype ?? this.doctype,
      helpers: helpers ?? this.helpers,
      filters: filters ?? this.filters,
      loader: loader ?? this.loader,
      cache: cache ?? this.cache,
      maxWhileIterations: maxWhileIterations ?? this.maxWhileIterations,
    );
  }
}
