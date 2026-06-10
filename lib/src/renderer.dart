import 'ast.dart';
import 'diagnostics.dart';
import 'evaluator.dart';
import 'options.dart';
import 'parser.dart';

class PugRenderer {
  PugRenderer(this.options)
      : evaluator = SafeExpressionEvaluator(
          helpers: options.effectiveHelpers,
          options: options,
        );

  final PugOptions options;
  final SafeExpressionEvaluator evaluator;
  final Map<String, PugDocument> _cache = {};
  bool _htmlDoctype = false;

  String render(PugDocument document, Map<String, Object?> locals) {
    final scope = EvalScope({...locals});
    final html = _renderDocument(document, scope, null);
    return options.pretty ? prettyHtml(html) : html;
  }

  String renderFile(String path, Map<String, Object?> locals) {
    final resolved = options.effectiveLoader.resolve(path);
    final document = _loadDocument(resolved);
    return render(document, locals);
  }

  PugDocument _loadDocument(String path) {
    if (options.cache && _cache.containsKey(path)) {
      return _cache[path]!;
    }
    final source = options.effectiveLoader.load(path);
    final document = PugParser(source, filename: path).parse();
    if (options.cache) _cache[path] = document;
    return document;
  }

  String _renderDocument(PugDocument document, EvalScope scope,
      Map<String, BlockOverride>? childBlocks) {
    if (document.children.whereType<DoctypeNode>().any(
        (node) => node.value.isEmpty || node.value.toLowerCase() == 'html')) {
      _htmlDoctype = true;
    }
    final extendsNode = document.children.whereType<ExtendsNode>().firstOrNull;
    if (extendsNode != null) {
      final blocks = _collectBlocks(document.children);
      if (childBlocks != null) {
        blocks.addAll(childBlocks);
      }
      final parentPath = options.effectiveLoader.resolve(
        extendsNode.path,
        from: extendsNode.span.filename,
      );
      return _renderDocument(_loadDocument(parentPath), scope, blocks);
    }
    return _renderNodes(document.children, scope, childBlocks, null);
  }

  String _renderNodes(
    List<PugNode> nodes,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    final buffer = StringBuffer();
    for (final node in nodes) {
      buffer.write(_renderNode(node, scope, blocks, yieldBlock));
    }
    return buffer.toString();
  }

  String _renderNode(
    PugNode node,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    return switch (node) {
      DoctypeNode() => _renderDoctype(node),
      TagNode() => _renderTag(node, scope, blocks, yieldBlock),
      TextNode() => node.unescaped
          ? node.text
          : _interpolate(node.text, scope, node.span, escape: true),
      LocalAssignmentNode() => _renderLocalAssignment(node, scope),
      ExpressionNode() => _stringify(
          evaluator.evaluate(node.expression, scope, node.span),
          escape: !node.unescaped,
        ),
      CommentNode() => node.buffered
          ? '<!--${node.text}${_commentBlock(node.blockText)}-->'
          : '',
      IfNode() => _renderIf(node, scope, blocks, yieldBlock),
      EachNode() => _renderEach(node, scope, blocks, yieldBlock),
      WhileNode() => _renderWhile(node, scope, blocks, yieldBlock),
      CaseNode() => _renderCase(node, scope, blocks, yieldBlock),
      IncludeNode() => _renderInclude(node, scope, blocks),
      ExtendsNode() => '',
      BlockNode() => _renderBlock(node, scope, blocks, yieldBlock),
      YieldBlockNode() =>
        yieldBlock == null ? '' : _renderNodes(yieldBlock, scope, blocks, null),
      MixinDeclarationNode() => _registerMixin(node, scope),
      MixinCallNode() => _renderMixinCall(node, scope, blocks),
      FilterNode() => _renderFilter(node, scope),
      PugDocument() => _renderNodes(node.children, scope, blocks, yieldBlock),
      _ => throw PugRenderException(
          'Unsupported AST node ${node.runtimeType}', node.span),
    };
  }

  String _renderLocalAssignment(LocalAssignmentNode node, EvalScope scope) {
    if (!options.localAssignmentsEnabled) {
      throw UnsupportedFeatureException(
        'Unbuffered assignment is unsupported: - var ${node.name} = ${node.expression}. Enable allowLocalAssignments or pass ${node.name} as a local.',
        node.span,
      );
    }
    scope.values[node.name] =
        evaluator.evaluate(node.expression, scope, node.span);
    return '';
  }

  String _renderTag(
    TagNode node,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    final attrs = _attributes(node, scope);
    final voidTag = _voidTags.contains(node.name);
    final buffer = StringBuffer('<${node.name}$attrs');
    if (node.selfClosing || voidTag) {
      buffer.write(_htmlDoctype ? '>' : '/>');
      return buffer.toString();
    }
    buffer.write('>');
    if (node.inlineText != null) {
      buffer.write(
          _interpolate(node.inlineText!, scope, node.span, escape: true));
    }
    if (node.bufferExpression != null) {
      buffer.write(_stringify(
        evaluator.evaluate(node.bufferExpression!, scope, node.span),
        escape: !node.unescapedBuffer,
      ));
    }
    if (node.textBlock != null) {
      buffer.write(_interpolate(node.textBlock!, scope, node.span,
          escape: node.name != 'script' && node.name != 'style'));
    }
    buffer.write(_renderNodes(node.children, scope, blocks, yieldBlock));
    buffer.write('</${node.name}>');
    return buffer.toString();
  }

  String _renderDoctype(DoctypeNode node) {
    final value = node.value.isEmpty ? 'html' : node.value;
    return switch (value) {
      'html' => '<!DOCTYPE html>',
      'xml' => '<?xml version="1.0" encoding="utf-8" ?>',
      'transitional' =>
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">',
      'strict' =>
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">',
      'frameset' =>
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">',
      '1.1' =>
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">',
      'basic' =>
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">',
      'mobile' =>
        '<!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">',
      'plist' =>
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
      _ => '<!DOCTYPE $value>',
    };
  }

  String _attributes(TagNode node, EvalScope scope) {
    final values = <String, Object?>{};
    final classValues = <Object?>[...node.classes];

    for (final attr in node.attributes) {
      final value = attr.expression == null
          ? true
          : evaluator.evaluate(attr.expression!, scope, node.span);
      if (attr.name == 'class') {
        classValues.add(value);
      } else if (attr.name == 'style' && value is Map) {
        values[attr.name] = _styleAttribute(value);
      } else {
        values[attr.name] = attr.escaped ? value : _RawAttribute(value);
      }
    }
    for (final spreadExpr in node.attributeSpreads) {
      final spread = evaluator.evaluate(spreadExpr, scope, node.span);
      if (spread is! Map) {
        throw PugRenderException('&attributes expects a map', node.span);
      }
      for (final entry in spread.entries) {
        if (entry.key == 'class') {
          classValues.add(entry.value);
        } else if (entry.key == 'style' && entry.value is Map) {
          values[entry.key.toString()] =
              _RawAttribute(_styleAttribute(entry.value as Map));
        } else {
          values[entry.key.toString()] = _RawAttribute(entry.value);
        }
      }
    }
    if (classValues.isNotEmpty) {
      final classes = _flattenClass(classValues)
          .where((value) => value.isNotEmpty)
          .join(' ');
      if (classes.isNotEmpty) values['class'] = classes;
    }
    if (node.id != null) values['id'] = node.id;

    final buffer = StringBuffer();
    final ordered = <MapEntry<String, Object?>>[
      if (values.containsKey('class'))
        MapEntry('class', values.remove('class')),
      if (values.containsKey('id')) MapEntry('id', values.remove('id')),
      ...values.entries,
    ];
    for (final entry in ordered) {
      final value = entry.value;
      if (value == null || value == false) continue;
      if (value == true) {
        if (_htmlDoctype) {
          buffer.write(' ${entry.key}');
        } else {
          buffer.write(' ${entry.key}="${entry.key}"');
        }
      } else if (value is _RawAttribute) {
        buffer.write(' ${entry.key}="${value.value ?? ''}"');
      } else {
        buffer.write(' ${entry.key}="${escapeHtml('$value')}"');
      }
    }
    return buffer.toString();
  }

  Iterable<String> _flattenClass(Iterable<Object?> values) sync* {
    for (final value in values) {
      if (value == null || value == false) continue;
      if (value is Iterable) {
        yield* _flattenClass(value);
      } else if (value is Map) {
        for (final entry in value.entries) {
          if (truthy(entry.value)) yield entry.key.toString();
        }
      } else {
        yield value.toString();
      }
    }
  }

  String _renderIf(
    IfNode node,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    for (final branch in node.branches) {
      if (truthy(evaluator.evaluate(branch.expression, scope, node.span))) {
        return _renderNodes(branch.children, scope, blocks, yieldBlock);
      }
    }
    return node.elseChildren == null
        ? ''
        : _renderNodes(node.elseChildren!, scope, blocks, yieldBlock);
  }

  String _renderEach(
    EachNode node,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    final value = evaluator.evaluate(node.iterableExpression, scope, node.span);
    final buffer = StringBuffer();
    var count = 0;
    void renderItem(Object? item, Object? key) {
      count++;
      final childValues = <String, Object?>{node.valueName: item};
      if (node.keyName != null) childValues[node.keyName!] = key;
      buffer.write(_renderNodes(
          node.children, scope.child(childValues), blocks, yieldBlock));
    }

    if (value is Map) {
      value.forEach((key, item) => renderItem(item, key));
    } else if (value is Iterable) {
      var key = 0;
      for (final item in value) {
        renderItem(item, key++);
      }
    }
    if (count == 0 && node.elseChildren != null) {
      return _renderNodes(node.elseChildren!, scope, blocks, yieldBlock);
    }
    return buffer.toString();
  }

  String _renderWhile(
    WhileNode node,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    final buffer = StringBuffer();
    var iterations = 0;
    while (truthy(evaluator.evaluate(node.expression, scope, node.span))) {
      if (++iterations > options.maxWhileIterations) {
        throw PugRenderException(
            'while exceeded maxWhileIterations', node.span);
      }
      buffer.write(_renderNodes(node.children, scope, blocks, yieldBlock));
    }
    return buffer.toString();
  }

  String _renderCase(
    CaseNode node,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    final value = evaluator.evaluate(node.expression, scope, node.span);
    for (final branch in node.branches) {
      if (value == evaluator.evaluate(branch.expression, scope, node.span)) {
        return _renderNodes(branch.children, scope, blocks, yieldBlock);
      }
    }
    return node.defaultChildren == null
        ? ''
        : _renderNodes(node.defaultChildren!, scope, blocks, yieldBlock);
  }

  String _renderInclude(
      IncludeNode node, EvalScope scope, Map<String, BlockOverride>? blocks) {
    final path =
        options.effectiveLoader.resolve(node.path, from: node.span.filename);
    try {
      return _renderDocument(_loadDocument(path), scope, blocks);
    } on PugIOException catch (error) {
      throw PugIOException(
        '${error.message} while processing include "${node.path}"',
        node.span,
      );
    }
  }

  String _renderBlock(
    BlockNode node,
    EvalScope scope,
    Map<String, BlockOverride>? blocks,
    List<PugNode>? yieldBlock,
  ) {
    final override = blocks?[node.name];
    if (override == null) {
      return _renderNodes(node.children, scope, blocks, yieldBlock);
    }
    final baseChildren =
        override.hasReplacement ? override.children : node.children;
    return _renderNodes(override.prepends, scope, blocks, yieldBlock) +
        _renderNodes(baseChildren, scope, blocks, yieldBlock) +
        _renderNodes(override.appends, scope, blocks, yieldBlock);
  }

  String _registerMixin(MixinDeclarationNode node, EvalScope scope) {
    scope.values['__mixin:${node.name}'] = node;
    return '';
  }

  String _renderMixinCall(
      MixinCallNode node, EvalScope scope, Map<String, BlockOverride>? blocks) {
    final declaration = scope.lookup('__mixin:${node.name}');
    if (declaration is! MixinDeclarationNode) {
      throw PugRenderException('Unknown mixin "${node.name}"', node.span);
    }
    final values = <String, Object?>{};
    for (var i = 0; i < declaration.params.length; i++) {
      final param = declaration.params[i];
      if (i < node.arguments.length) {
        values[param.name] =
            evaluator.evaluate(node.arguments[i], scope, node.span);
      } else if (param.defaultExpression != null) {
        values[param.name] =
            evaluator.evaluate(param.defaultExpression!, scope, node.span);
      } else {
        values[param.name] = null;
      }
    }
    values['attributes'] = _mixinAttributes(node, scope);
    return _renderNodes(
        declaration.children, scope.child(values), blocks, node.children);
  }

  Map<String, Object?> _mixinAttributes(MixinCallNode node, EvalScope scope) {
    final attrs = <String, Object?>{};
    for (final attr in node.attributes) {
      attrs[attr.name] = attr.expression == null
          ? true
          : evaluator.evaluate(attr.expression!, scope, node.span);
    }
    for (final spreadExpr in node.attributeSpreads) {
      final spread = evaluator.evaluate(spreadExpr, scope, node.span);
      if (spread is Map) {
        for (final entry in spread.entries) {
          attrs[entry.key.toString()] = entry.value;
        }
      }
    }
    return attrs;
  }

  String _renderFilter(FilterNode node, EvalScope scope) {
    final attrs = <String, Object?>{};
    for (final attr in node.attributes) {
      attrs[attr.name] = attr.expression == null
          ? true
          : evaluator.evaluate(attr.expression!, scope, node.span);
    }
    final filter = options.filters[node.name];
    if (filter == null) {
      if (node.name == 'plain' || node.name == 'text') return node.text;
      throw UnsupportedFeatureException(
          'Unknown filter "${node.name}"', node.span);
    }
    return filter(node.text, attrs);
  }

  Map<String, BlockOverride> _collectBlocks(List<PugNode> nodes) {
    final blocks = <String, BlockOverride>{};
    for (final node in nodes.whereType<BlockNode>()) {
      blocks.update(
        node.name,
        (existing) => existing.add(node.mode, node.children),
        ifAbsent: () =>
            const BlockOverride.empty().add(node.mode, node.children),
      );
    }
    return blocks;
  }

  String _interpolate(String text, EvalScope scope, PugSourceSpan span,
      {required bool escape}) {
    return text.replaceAllMapped(RegExp(r'([#!])\{([^}]*)\}'), (match) {
      final unescaped = match.group(1) == '!';
      return _stringify(
        evaluator.evaluate(match.group(2)!, scope, span),
        escape: escape && !unescaped,
      );
    });
  }

  String _stringify(Object? value, {required bool escape}) {
    final text = value?.toString() ?? '';
    return escape ? escapeHtml(text) : text;
  }

  String _commentBlock(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAll('\n', '');
  }

  String _styleAttribute(Map<Object?, Object?> value) {
    final buffer = StringBuffer();
    for (final entry in value.entries) {
      if (entry.value == null || entry.value == false) continue;
      buffer.write('${entry.key}:${entry.value};');
    }
    return buffer.toString();
  }
}

class BlockOverride {
  const BlockOverride(
    this.mode,
    this.children,
    this.prepends,
    this.appends, {
    required this.hasReplacement,
  });
  const BlockOverride.empty()
      : mode = BlockMode.replace,
        children = const [],
        prepends = const [],
        appends = const [],
        hasReplacement = false;

  final BlockMode mode;
  final List<PugNode> children;
  final List<PugNode> prepends;
  final List<PugNode> appends;
  final bool hasReplacement;

  BlockOverride add(BlockMode mode, List<PugNode> nodes) {
    return switch (mode) {
      BlockMode.replace => BlockOverride(
          mode,
          nodes,
          prepends,
          appends,
          hasReplacement: true,
        ),
      BlockMode.prepend => BlockOverride(
          this.mode,
          children,
          [...prepends, ...nodes],
          appends,
          hasReplacement: hasReplacement,
        ),
      BlockMode.append => BlockOverride(
          this.mode,
          children,
          prepends,
          [...appends, ...nodes],
          hasReplacement: hasReplacement,
        ),
    };
  }
}

class _RawAttribute {
  const _RawAttribute(this.value);
  final Object? value;
}

String escapeHtml(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

const _voidTags = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

String prettyHtml(String html) {
  final tokens = RegExp(r'<!--.*?-->|<![^>]*>|<[^>]+>|[^<]+', dotAll: true)
      .allMatches(html)
      .map((match) => match.group(0)!)
      .where((token) => token.isNotEmpty)
      .toList();
  final buffer = StringBuffer();
  var indent = 0;
  for (final token in tokens) {
    if (token.trim().isEmpty) continue;
    if (token.startsWith('</')) {
      indent = indent > 0 ? indent - 1 : 0;
      _writePrettyLine(buffer, indent, token);
    } else if (_isPrettyRawTag(token)) {
      _writePrettyLine(buffer, indent, token);
      indent++;
    } else if (token.startsWith('<')) {
      _writePrettyLine(buffer, indent, token);
      if (!_isPrettyDoctype(token) &&
          !_isPrettyClosing(token) &&
          !_isPrettyVoid(token)) {
        indent++;
      }
    } else {
      final text = token.trim();
      if (text.isNotEmpty) {
        _writePrettyLine(buffer, indent, text);
      }
    }
  }
  final pretty = buffer.toString();
  final collapsed = _collapsePrettyInlineText(pretty);
  return collapsed.endsWith('\n')
      ? collapsed.substring(0, collapsed.length - 1)
      : collapsed;
}

void _writePrettyLine(StringBuffer buffer, int indent, String value) {
  buffer
    ..write('  ' * indent)
    ..writeln(value);
}

bool _isPrettyDoctype(String token) => token.startsWith('<!');

bool _isPrettyClosing(String token) =>
    token.startsWith('</') || token.endsWith('/>');

bool _isPrettyVoid(String token) {
  final match = RegExp(r'^<([A-Za-z][\w:-]*)').firstMatch(token);
  return match != null && _voidTags.contains(match.group(1));
}

bool _isPrettyRawTag(String token) =>
    RegExp(r'^<(script|style)(\s|>)', caseSensitive: false).hasMatch(token);

String _collapsePrettyInlineText(String html) {
  var result = html;
  final pattern = RegExp(
    r'^([ ]*)<([A-Za-z][\w:-]*)([^>]*)>\n[ ]{2,}([^<\n]+)\n\1</\2>$',
    multiLine: true,
  );
  while (pattern.hasMatch(result)) {
    result = result.replaceAllMapped(pattern, (match) {
      final indent = match.group(1)!;
      final tag = match.group(2)!;
      final attrs = match.group(3)!;
      final text = match.group(4)!.trim();
      return '$indent<$tag$attrs>$text</$tag>';
    });
  }
  return result;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
