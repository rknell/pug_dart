import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'diagnostics.dart';

typedef PugHelper = Object? Function(List<Object?> args);
typedef PugFilter = String Function(String text, Map<String, Object?> attrs);

enum PugCompatibility { strict, nodeMigration }

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
    this.compatibility = PugCompatibility.strict,
    this.allowLocalAssignments = false,
    this.simpleTemplateLiterals = false,
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
  final PugCompatibility compatibility;
  final bool allowLocalAssignments;
  final bool simpleTemplateLiterals;
  final Map<String, PugHelper> helpers;
  final Map<String, PugFilter> filters;
  final PugTemplateLoader? loader;
  final bool cache;
  final int maxWhileIterations;

  PugTemplateLoader get effectiveLoader =>
      loader ?? FileSystemPugTemplateLoader(basedir: basedir);

  bool get localAssignmentsEnabled =>
      allowLocalAssignments || compatibility == PugCompatibility.nodeMigration;

  bool get simpleTemplateLiteralsEnabled =>
      simpleTemplateLiterals || compatibility == PugCompatibility.nodeMigration;

  bool get nodeMigrationEnabled =>
      compatibility == PugCompatibility.nodeMigration;

  Map<String, PugHelper> get effectiveHelpers {
    if (!nodeMigrationEnabled) return helpers;
    return {...nodeMigrationHelpers, ...helpers};
  }

  PugOptions copyWith({
    String? filename,
    String? basedir,
    bool? pretty,
    String? doctype,
    PugCompatibility? compatibility,
    bool? allowLocalAssignments,
    bool? simpleTemplateLiterals,
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
      compatibility: compatibility ?? this.compatibility,
      allowLocalAssignments:
          allowLocalAssignments ?? this.allowLocalAssignments,
      simpleTemplateLiterals:
          simpleTemplateLiterals ?? this.simpleTemplateLiterals,
      helpers: helpers ?? this.helpers,
      filters: filters ?? this.filters,
      loader: loader ?? this.loader,
      cache: cache ?? this.cache,
      maxWhileIterations: maxWhileIterations ?? this.maxWhileIterations,
    );
  }
}

final Map<String, PugHelper> nodeMigrationHelpers = {
  'JSON': (_) => {
        'stringify': (List<Object?> args) => jsonEncode(args.firstOrNull),
      },
  'Number': (args) => _number(args.firstOrNull),
  'String': (args) => args.firstOrNull?.toString() ?? '',
  'Math': (_) => {
        'round': (List<Object?> args) => _number(args.firstOrNull).round(),
        'floor': (List<Object?> args) => _number(args.firstOrNull).floor(),
        'ceil': (List<Object?> args) => _number(args.firstOrNull).ceil(),
        'min': (List<Object?> args) =>
            args.map(_number).fold<num>(double.infinity, math.min),
        'max': (List<Object?> args) =>
            args.map(_number).fold<num>(double.negativeInfinity, math.max),
      },
};

num _number(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  if (value == true) return 1;
  return 0;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
