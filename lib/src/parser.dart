import 'ast.dart';
import 'diagnostics.dart';

class PugParser {
  PugParser(this.source, {required this.filename})
      : _lines = source.replaceAll('\r\n', '\n').split('\n');

  final String source;
  final String filename;
  final List<String> _lines;
  int _index = 0;

  PugDocument parse() {
    final children = _parseBlock(0);
    return PugDocument(
        _span(1, 1, _lines.isEmpty ? '' : _lines.first), children);
  }

  List<PugNode> _parseBlock(int indent) {
    final nodes = <PugNode>[];
    while (_index < _lines.length) {
      final raw = _lines[_index];
      if (raw.trim().isEmpty) {
        _index++;
        continue;
      }
      final currentIndent = _indent(raw);
      if (currentIndent < indent) {
        break;
      }
      if (currentIndent > indent) {
        throw PugParseException('Unexpected indentation', _lineSpan(_index));
      }
      nodes.add(_parseLine(indent));
    }
    return _foldConditionalsAndEach(nodes);
  }

  PugNode _parseLine(int indent) {
    final raw = _lines[_index];
    final trimmed = raw.trimLeft();
    final span = _lineSpan(_index);
    _index++;

    if (trimmed.startsWith('doctype')) {
      return DoctypeNode(span, trimmed.substring('doctype'.length).trim());
    }
    if (trimmed.startsWith('extends ')) {
      return ExtendsNode(span, _stripQuotes(trimmed.substring(8).trim()));
    }
    if (trimmed.startsWith('include ')) {
      return IncludeNode(span, _stripQuotes(trimmed.substring(8).trim()));
    }
    if (trimmed.startsWith('//-')) {
      final blockText = _readTextBlockNested(indent);
      return CommentNode(span, trimmed.substring(3),
          buffered: false, blockText: blockText);
    }
    if (trimmed.startsWith('//')) {
      final blockText = _readTextBlockNested(indent);
      return CommentNode(span, trimmed.substring(2), blockText: blockText);
    }
    if (trimmed.startsWith('|')) {
      final text = trimmed.length == 1 ? '' : trimmed.substring(1).trimLeft();
      return TextNode(
          span, _nextLineAtIndentStartsWith(indent, '|') ? '$text\n' : text);
    }
    if (trimmed.startsWith('!=')) {
      return ExpressionNode(span, trimmed.substring(2).trim(), unescaped: true);
    }
    if (trimmed.startsWith('=')) {
      return ExpressionNode(span, trimmed.substring(1).trim());
    }
    if (trimmed.startsWith('if ')) {
      return IfNode(
          span,
          [IfBranch(trimmed.substring(3).trim(), _parseNestedBlock(indent))],
          null);
    }
    if (trimmed.startsWith('unless ')) {
      return IfNode(
          span,
          [
            IfBranch(
                '!(${trimmed.substring(7).trim()})', _parseNestedBlock(indent))
          ],
          null);
    }
    if (trimmed.startsWith('else if ')) {
      return _ElseIfMarker(
          span, trimmed.substring(8).trim(), _parseNestedBlock(indent));
    }
    if (trimmed == 'else') {
      return _ElseMarker(span, _parseNestedBlock(indent));
    }
    if (trimmed.startsWith('each ')) {
      return _parseEach(span, trimmed, indent);
    }
    if (trimmed.startsWith('while ')) {
      return WhileNode(
          span, trimmed.substring(6).trim(), _parseNestedBlock(indent));
    }
    if (trimmed.startsWith('case ')) {
      return _parseCase(span, trimmed, indent);
    }
    if (trimmed.startsWith('block')) {
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length == 1) {
        return YieldBlockNode(span);
      }
      return BlockNode(
          span, parts[1], BlockMode.replace, _parseNestedBlock(indent));
    }
    if (trimmed.startsWith('append ')) {
      return BlockNode(span, trimmed.substring(7).trim(), BlockMode.append,
          _parseNestedBlock(indent));
    }
    if (trimmed.startsWith('prepend ')) {
      return BlockNode(span, trimmed.substring(8).trim(), BlockMode.prepend,
          _parseNestedBlock(indent));
    }
    if (trimmed.startsWith('mixin ')) {
      return _parseMixin(span, trimmed, indent);
    }
    if (trimmed.startsWith('+')) {
      return _parseMixinCall(span, trimmed, indent);
    }
    if (trimmed.startsWith(':')) {
      return _parseFilter(span, trimmed, indent);
    }
    if (trimmed.startsWith('-')) {
      throw UnsupportedFeatureException(
        'Unbuffered JavaScript code is not supported; precompute values in Dart locals or helpers.',
        span,
      );
    }
    final expansion = _findBlockExpansion(trimmed);
    if (expansion != -1) {
      return _parseExpandedTag(span, trimmed, expansion, indent);
    }
    return _parseTag(span, trimmed, indent);
  }

  EachNode _parseEach(PugSourceSpan span, String trimmed, int indent) {
    final match = RegExp(
            r'^each\s+([A-Za-z_$][\w$]*)(?:\s*,\s*([A-Za-z_$][\w$]*))?\s+in\s+(.+)$')
        .firstMatch(trimmed);
    if (match == null) {
      throw PugParseException('Invalid each syntax', span);
    }
    return EachNode(
      span,
      valueName: match.group(1)!,
      keyName: match.group(2),
      iterableExpression: match.group(3)!.trim(),
      children: _parseNestedBlock(indent),
      elseChildren: null,
    );
  }

  MixinDeclarationNode _parseMixin(
      PugSourceSpan span, String trimmed, int indent) {
    final match = RegExp(r'^mixin\s+([A-Za-z_$][\w$]*)(?:\((.*)\))?$')
        .firstMatch(trimmed);
    if (match == null) {
      throw PugParseException('Invalid mixin declaration', span);
    }
    final params = _splitTopLevel(match.group(2) ?? '')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
      final pieces = _splitAssignment(part);
      return MixinParam(pieces.$1.trim(), pieces.$2?.trim());
    }).toList();
    return MixinDeclarationNode(
        span, match.group(1)!, params, _parseNestedBlock(indent));
  }

  MixinCallNode _parseMixinCall(
      PugSourceSpan span, String trimmed, int indent) {
    final body = trimmed.substring(1);
    final nameMatch = RegExp(r'^([A-Za-z_$][\w$]*)').firstMatch(body);
    if (nameMatch == null) {
      throw PugParseException('Invalid mixin call', span);
    }
    final name = nameMatch.group(1)!;
    var rest = body.substring(name.length).trimLeft();
    var args = <String>[];
    if (rest.startsWith('(')) {
      final result = _readBalanced(rest, 0, '(', ')');
      args = _splitTopLevel(result.content)
          .where((part) => part.trim().isNotEmpty)
          .toList();
      rest = rest.substring(result.end + 1).trimLeft();
    }
    final attrs = <PugAttribute>[];
    final spreads = <String>[];
    if (rest.startsWith('(')) {
      final result = _readBalanced(rest, 0, '(', ')');
      _parseAttributes(result.content, attrs, spreads);
    }
    return MixinCallNode(
        span, name, args, attrs, spreads, _parseNestedBlock(indent));
  }

  FilterNode _parseFilter(PugSourceSpan span, String trimmed, int indent) {
    final match =
        RegExp(r'^:([A-Za-z][\w-]*)(?:\((.*)\))?$').firstMatch(trimmed);
    if (match == null) {
      throw PugParseException('Invalid filter syntax', span);
    }
    final attrs = <PugAttribute>[];
    final spreads = <String>[];
    _parseAttributes(match.group(2) ?? '', attrs, spreads);
    if (spreads.isNotEmpty) {
      throw PugParseException(
          'Filter attribute spreads are not supported', span);
    }
    return FilterNode(
        span, match.group(1)!, _readTextBlockNested(indent), attrs);
  }

  CaseNode _parseCase(PugSourceSpan span, String trimmed, int indent) {
    final branchIndent = _nextIndent();
    if (branchIndent == null || branchIndent <= indent) {
      return CaseNode(span, trimmed.substring(5).trim(), const [], null);
    }
    final branches = <CaseBranch>[];
    List<PugNode>? defaultChildren;
    while (_index < _lines.length) {
      final raw = _lines[_index];
      if (raw.trim().isEmpty) {
        _index++;
        continue;
      }
      final currentIndent = _indent(raw);
      if (currentIndent < branchIndent) break;
      if (currentIndent != branchIndent) {
        throw PugParseException(
            'Unexpected case indentation', _lineSpan(_index));
      }
      final branchSpan = _lineSpan(_index);
      final branch = raw.trimLeft();
      _index++;
      if (branch.startsWith('when ')) {
        branches.add(CaseBranch(
          branch.substring(5).trim(),
          _parseNestedBlock(branchIndent),
        ));
      } else if (branch == 'default') {
        defaultChildren = _parseNestedBlock(branchIndent);
      } else {
        throw PugParseException('Expected when or default', branchSpan);
      }
    }
    return CaseNode(
        span, trimmed.substring(5).trim(), branches, defaultChildren);
  }

  TagNode _parseTag(PugSourceSpan span, String trimmed, int indent) {
    var rest = trimmed;
    var name = 'div';
    if (RegExp(r'^[A-Za-z][\w:-]*').hasMatch(rest)) {
      final match = RegExp(r'^[A-Za-z][\w:-]*').firstMatch(rest)!;
      name = match.group(0)!;
      rest = rest.substring(name.length);
    }

    String? id;
    final classes = <String>[];
    final attrs = <PugAttribute>[];
    final spreads = <String>[];
    var selfClosing = false;
    var textBlock = false;

    while (rest.isNotEmpty) {
      if (rest.startsWith('#')) {
        final match = RegExp(r'^#([\w-]+)').firstMatch(rest);
        if (match == null) break;
        id = match.group(1);
        rest = rest.substring(match.group(0)!.length);
      } else if (rest.startsWith('.')) {
        if (rest == '.') {
          textBlock = true;
          rest = '';
          break;
        }
        final match = RegExp(r'^\.([\w:-]+)').firstMatch(rest);
        if (match == null) break;
        classes.add(match.group(1)!);
        rest = rest.substring(match.group(0)!.length);
      } else if (rest.startsWith('(')) {
        final result = _readBalancedFromTemplate(rest, indent);
        _parseAttributes(result.content, attrs, spreads);
        rest = result.source.substring(result.end + 1);
      } else if (rest.startsWith('&attributes')) {
        final start = rest.indexOf('(');
        if (start == -1) {
          throw PugParseException('Invalid attribute spread', span);
        }
        final result = _readBalanced(rest, start, '(', ')');
        spreads.add(result.content);
        rest = rest.substring(result.end + 1);
      } else if (rest.startsWith('/')) {
        selfClosing = true;
        rest = rest.substring(1);
      } else {
        break;
      }
    }

    rest = rest.trimLeft();
    String? inlineText;
    String? bufferExpression;
    var unescapedBuffer = false;
    if (rest.startsWith('!=')) {
      bufferExpression = rest.substring(2).trim();
      unescapedBuffer = true;
    } else if (rest.startsWith('=')) {
      bufferExpression = rest.substring(1).trim();
    } else if (rest.isNotEmpty) {
      inlineText = rest;
    }

    final blockText = textBlock ? _readTextBlockNested(indent) : null;
    final children =
        blockText == null ? _parseNestedBlock(indent) : <PugNode>[];

    return TagNode(
      span,
      name: name,
      id: id,
      classes: classes,
      attributes: attrs,
      attributeSpreads: spreads,
      children: children,
      inlineText: inlineText,
      bufferExpression: bufferExpression,
      unescapedBuffer: unescapedBuffer,
      textBlock: blockText,
      selfClosing: selfClosing,
    );
  }

  PugNode _parseExpandedTag(
      PugSourceSpan span, String trimmed, int expansion, int indent) {
    final parent =
        _parseTag(span, trimmed.substring(0, expansion).trimRight(), indent);
    final childSource = trimmed.substring(expansion + 1).trimLeft();
    final child = PugParser(childSource, filename: filename).parse().children;
    return TagNode(
      parent.span,
      name: parent.name,
      id: parent.id,
      classes: parent.classes,
      attributes: parent.attributes,
      attributeSpreads: parent.attributeSpreads,
      children: [...parent.children, ...child],
      inlineText: parent.inlineText,
      bufferExpression: parent.bufferExpression,
      unescapedBuffer: parent.unescapedBuffer,
      textBlock: parent.textBlock,
      selfClosing: parent.selfClosing,
    );
  }

  List<PugNode> _foldConditionalsAndEach(List<PugNode> nodes) {
    final folded = <PugNode>[];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is IfNode) {
        final branches = [...node.branches];
        List<PugNode>? elseChildren;
        while (i + 1 < nodes.length &&
            (nodes[i + 1] is _ElseIfMarker || nodes[i + 1] is _ElseMarker)) {
          final next = nodes[++i];
          if (next is _ElseIfMarker) {
            branches.add(IfBranch(next.expression, next.children));
          } else if (next is _ElseMarker) {
            elseChildren = next.children;
            break;
          }
        }
        folded.add(IfNode(node.span, branches, elseChildren));
      } else if (node is EachNode &&
          i + 1 < nodes.length &&
          nodes[i + 1] is _ElseMarker) {
        final marker = nodes[++i] as _ElseMarker;
        folded.add(EachNode(
          node.span,
          valueName: node.valueName,
          keyName: node.keyName,
          iterableExpression: node.iterableExpression,
          children: node.children,
          elseChildren: marker.children,
        ));
      } else if (node is _ElseIfMarker || node is _ElseMarker) {
        throw PugParseException(
            'Unexpected ${node is _ElseMarker ? 'else' : 'else if'}',
            node.span);
      } else {
        folded.add(node);
      }
    }
    return folded;
  }

  void _parseAttributes(
      String source, List<PugAttribute> attrs, List<String> spreads) {
    for (final raw in _splitTopLevel(source, splitSpaces: true)) {
      final attr = raw.trim();
      if (attr.isEmpty) continue;
      if (attr.startsWith('&attributes')) {
        final start = attr.indexOf('(');
        if (start == -1) {
          throw PugParseException(
              'Invalid attribute spread', _lineSpan(_index - 1));
        }
        spreads.add(_readBalanced(attr, start, '(', ')').content);
        continue;
      }
      final eq = _findTopLevel(attr, '=');
      if (eq == -1) {
        attrs.add(PugAttribute(_attributeName(attr), null));
      } else {
        var name = attr.substring(0, eq).trim();
        var expr = attr.substring(eq + 1).trim();
        var escaped = true;
        if (name.endsWith('!')) {
          escaped = false;
          name = name.substring(0, name.length - 1);
        }
        if (expr.startsWith('!=')) {
          escaped = false;
          expr = expr.substring(2).trim();
        }
        attrs.add(PugAttribute(_attributeName(name), expr, escaped: escaped));
      }
    }
  }

  String _readTextBlock(int indent) {
    final buffer = StringBuffer();
    while (_index < _lines.length) {
      final raw = _lines[_index];
      if (raw.trim().isEmpty) {
        if (!_hasFollowingIndentedLine(_index + 1, indent)) {
          _index++;
          break;
        }
        buffer.writeln();
        _index++;
        continue;
      }
      final currentIndent = _indent(raw);
      if (currentIndent < indent) break;
      final remove = currentIndent >= indent ? indent : currentIndent;
      buffer.writeln(raw.substring(remove));
      _index++;
    }
    final text = buffer.toString();
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  List<PugNode> _parseNestedBlock(int parentIndent) {
    final childIndent = _nextIndent();
    if (childIndent == null || childIndent <= parentIndent) {
      return [];
    }
    return _parseBlock(childIndent);
  }

  String _readTextBlockNested(int parentIndent) {
    final childIndent = _nextIndent();
    if (childIndent == null || childIndent <= parentIndent) {
      return '';
    }
    return _readTextBlock(childIndent);
  }

  int? _nextIndent() {
    for (var i = _index; i < _lines.length; i++) {
      if (_lines[i].trim().isNotEmpty) {
        return _indent(_lines[i]);
      }
    }
    return null;
  }

  bool _hasFollowingIndentedLine(int start, int indent) {
    for (var i = start; i < _lines.length; i++) {
      if (_lines[i].trim().isEmpty) continue;
      return _indent(_lines[i]) >= indent;
    }
    return false;
  }

  bool _nextLineAtIndentStartsWith(int indent, String prefix) {
    for (var i = _index; i < _lines.length; i++) {
      if (_lines[i].trim().isEmpty) continue;
      return _indent(_lines[i]) == indent &&
          _lines[i].trimLeft().startsWith(prefix);
    }
    return false;
  }

  int _indent(String line) {
    var count = 0;
    for (final unit in line.codeUnits) {
      if (unit == 32) {
        count++;
      } else if (unit == 9) {
        count += 2;
      } else {
        break;
      }
    }
    return count;
  }

  PugSourceSpan _lineSpan(int index) =>
      _span(index + 1, _indent(_lines[index]) + 1, _lines[index]);

  PugSourceSpan _span(int line, int column, String sourceLine) => PugSourceSpan(
      filename: filename, line: line, column: column, sourceLine: sourceLine);
}

extension on PugParser {
  ({String content, int end, String source}) _readBalancedFromTemplate(
      String source, int parentIndent) {
    var combined = source;
    while (true) {
      try {
        final result = _readBalanced(combined, 0, '(', ')');
        return (content: result.content, end: result.end, source: combined);
      } on PugParseException {
        if (_index >= _lines.length) rethrow;
        final next = _lines[_index];
        if (next.trim().isEmpty) rethrow;
        if (_indent(next) <= parentIndent && !next.trimLeft().startsWith(')')) {
          rethrow;
        }
        combined = '$combined ${next.trim()}';
        _index++;
      }
    }
  }
}

class _ElseIfMarker extends PugNode {
  const _ElseIfMarker(super.span, this.expression, this.children);
  final String expression;
  final List<PugNode> children;
}

class _ElseMarker extends PugNode {
  const _ElseMarker(super.span, this.children);
  final List<PugNode> children;
}

String _stripQuotes(String value) {
  if (value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _attributeName(String value) => _stripQuotes(value.trim());

int _findBlockExpansion(String source) {
  var depth = 0;
  var hasTopLevelQuestion = false;
  String? quote;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
    } else if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char)) {
      depth--;
    } else if (depth == 0 && char == '?') {
      hasTopLevelQuestion = true;
    } else if (depth == 0 &&
        char == ':' &&
        !hasTopLevelQuestion &&
        i + 1 < source.length &&
        source[i + 1] == ' ') {
      return i;
    }
  }
  return -1;
}

({String content, int end}) _readBalanced(
    String source, int start, String open, String close) {
  var depth = 0;
  String? quote;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == open) depth++;
    if (char == close) {
      depth--;
      if (depth == 0) {
        return (content: source.substring(start + 1, i), end: i);
      }
    }
  }
  throw PugParseException('Unclosed $open');
}

List<String> _splitTopLevel(
  String source, {
  String separator = ',',
  bool splitSpaces = false,
}) {
  final parts = <String>[];
  var depth = 0;
  var ternaryDepth = 0;
  String? quote;
  var start = 0;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
    } else if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char)) {
      depth--;
    } else if (depth == 0 && char == '?') {
      ternaryDepth++;
    } else if (depth == 0 &&
        ternaryDepth == 0 &&
        (char == separator ||
            (splitSpaces && char == ' ' && _spaceStartsAttribute(source, i)))) {
      final part = source.substring(start, i).trim();
      if (part.isNotEmpty) parts.add(part);
      start = i + 1;
      while (start < source.length && source[start] == ' ') {
        start++;
      }
      i = start - 1;
    }
  }
  final last = source.substring(start).trim();
  if (last.isNotEmpty) parts.add(last);
  return parts;
}

bool _spaceStartsAttribute(String source, int index) {
  var previous = index - 1;
  while (previous >= 0 && source[previous] == ' ') {
    previous--;
  }
  if (previous >= 0 && '&|?:+-*/%<>=,'.contains(source[previous])) {
    return false;
  }
  var next = index + 1;
  while (next < source.length && source[next] == ' ') {
    next++;
  }
  if (next >= source.length) return false;
  if ('&|?:+-*/%<>=,'.contains(source[next])) return false;
  return true;
}

int _findTopLevel(String source, String target) {
  var depth = 0;
  String? quote;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
    } else if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char)) {
      depth--;
    } else if (depth == 0 && char == target) {
      return i;
    }
  }
  return -1;
}

(String, String?) _splitAssignment(String source) {
  final index = _findTopLevel(source, '=');
  if (index == -1) return (source, null);
  return (source.substring(0, index), source.substring(index + 1));
}
