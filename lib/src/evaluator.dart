import 'diagnostics.dart';
import 'options.dart';

class EvalScope {
  EvalScope(this.values, {this.parent});

  final Map<String, Object?> values;
  final EvalScope? parent;

  Object? lookup(String name) {
    if (values.containsKey(name)) return values[name];
    return parent?.lookup(name);
  }

  EvalScope child([Map<String, Object?> values = const {}]) =>
      EvalScope({...values}, parent: this);
}

class SafeExpressionEvaluator {
  SafeExpressionEvaluator({
    required this.helpers,
    required this.options,
  });

  final Map<String, PugHelper> helpers;
  final PugOptions options;

  Object? evaluate(String source, EvalScope scope, [PugSourceSpan? span]) {
    _rejectUnsupported(source, span);
    if (options.simpleTemplateLiteralsEnabled &&
        source.startsWith('`') &&
        source.endsWith('`')) {
      return _evaluateTemplateLiteral(source, scope, span);
    }
    final parser =
        _ExpressionParser(_Scanner(source, span).scan(), helpers, scope, span);
    return parser.parse();
  }

  void _rejectUnsupported(String source, PugSourceSpan? span) {
    if (source.contains('`') && !options.simpleTemplateLiteralsEnabled) {
      throw UnsupportedFeatureException(
        'Template literals are unsupported. Use string concatenation or enable simpleTemplateLiterals.',
        span,
      );
    }
    if (RegExp(r'\b(JSON|Math)\s*\.').hasMatch(source) &&
        !options.nodeMigrationEnabled) {
      throw UnsupportedFeatureException(
        '$source is not enabled. Use PugCompatibility.nodeMigration or register an explicit Dart helper.',
        span,
      );
    }
    final unsupported = [
      RegExp(r'\bnew\s+'),
      RegExp(r'=>'),
      RegExp(r'\bfunction\b'),
      RegExp(r'\b(var|let|const)\b'),
      RegExp(r'\b(Date|moment)\s*\.'),
    ];
    for (final pattern in unsupported) {
      if (pattern.hasMatch(source)) {
        throw UnsupportedFeatureException(
          'Unsupported JavaScript expression "$source"; precompute it in Dart locals or expose an explicit helper.',
          span,
        );
      }
    }
  }

  String _evaluateTemplateLiteral(
      String source, EvalScope scope, PugSourceSpan? span) {
    final body = source.substring(1, source.length - 1);
    final buffer = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final char = body[i];
      if (char == r'\') {
        if (i + 1 >= body.length) {
          buffer.write(char);
        } else {
          final escaped = body[++i];
          buffer.write(switch (escaped) {
            '`' => '`',
            r'\' => r'\',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            _ => escaped,
          });
        }
      } else if (char == r'$' && i + 1 < body.length && body[i + 1] == '{') {
        final end = _findTemplateExpressionEnd(body, i + 2, span);
        final expression = body.substring(i + 2, end);
        buffer.write(evaluate(expression, scope, span)?.toString() ?? '');
        i = end;
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  int _findTemplateExpressionEnd(
      String source, int start, PugSourceSpan? span) {
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
      } else if ('([{'.contains(char)) {
        depth++;
      } else if (')]}'.contains(char)) {
        if (char == '}' && depth == 0) return i;
        depth--;
      } else if (char == '}' && depth == 0) {
        return i;
      }
    }
    throw PugRenderException('Unterminated template literal expression', span);
  }
}

bool truthy(Object? value) {
  if (value == null || value == false) return false;
  if (value is num) return value != 0;
  if (value is String) return value.isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

class _ExpressionParser {
  _ExpressionParser(this.tokens, this.helpers, this.scope, this.span);

  final List<_Token> tokens;
  final Map<String, PugHelper> helpers;
  final EvalScope scope;
  final PugSourceSpan? span;
  int index = 0;

  Object? parse() {
    final value = _ternary();
    _expect(_TokenType.eof);
    return value;
  }

  Object? _ternary() {
    final condition = _or();
    if (_match('?')) {
      final whenTrue = _or();
      _consume(':');
      final whenFalse = _ternary();
      return truthy(condition) ? whenTrue : whenFalse;
    }
    return condition;
  }

  Object? _or() {
    var left = _and();
    while (_match('||') || _matchWord('or')) {
      final right = _and();
      left = truthy(left) ? left : right;
    }
    return left;
  }

  Object? _and() {
    var left = _equality();
    while (_match('&&') || _matchWord('and')) {
      final right = _equality();
      left = truthy(left) ? right : left;
    }
    return left;
  }

  Object? _equality() {
    var left = _comparison();
    while (true) {
      if (_match('==') || _match('===')) {
        left = left == _comparison();
      } else if (_match('!=') || _match('!==')) {
        left = left != _comparison();
      } else {
        return left;
      }
    }
  }

  Object? _comparison() {
    var left = _term();
    while (true) {
      if (_match('<')) {
        left = _compare(left, _term()) < 0;
      } else if (_match('<=')) {
        left = _compare(left, _term()) <= 0;
      } else if (_match('>')) {
        left = _compare(left, _term()) > 0;
      } else if (_match('>=')) {
        left = _compare(left, _term()) >= 0;
      } else {
        return left;
      }
    }
  }

  Object? _term() {
    var left = _factor();
    while (true) {
      if (_match('+')) {
        final right = _factor();
        left = left is String || right is String
            ? '${left ?? ''}${right ?? ''}'
            : _num(left) + _num(right);
      } else if (_match('-')) {
        left = _num(left) - _num(_factor());
      } else {
        return left;
      }
    }
  }

  Object? _factor() {
    var left = _unary();
    while (true) {
      if (_match('*')) {
        left = _num(left) * _num(_unary());
      } else if (_match('/')) {
        left = _num(left) / _num(_unary());
      } else if (_match('%')) {
        left = _num(left) % _num(_unary());
      } else {
        return left;
      }
    }
  }

  Object? _unary() {
    if (_match('!') || _matchWord('not')) return !truthy(_unary());
    if (_match('-')) return -_num(_unary());
    return _postfix();
  }

  Object? _postfix() {
    var value = _primary();
    while (true) {
      if (_match('.')) {
        final name = _consumeIdentifier();
        if (_check('(') && name == 'toString') {
          final target = value;
          value = (List<Object?> args) => target?.toString();
        } else if (_check('(') && name == 'toFixed') {
          final target = value;
          value = (List<Object?> args) {
            final digits = args.isEmpty ? 0 : _num(args.first).toInt();
            return _num(target).toStringAsFixed(digits);
          };
        } else if (_check('(') && name == 'join') {
          final target = value;
          value = (List<Object?> args) {
            final separator = args.isEmpty ? ',' : '${args.first ?? ''}';
            if (target is Iterable) return target.join(separator);
            return '';
          };
        } else if (_check('(') && name == 'includes') {
          final target = value;
          value = (List<Object?> args) {
            final needle = args.firstOrNull;
            if (target is String) return target.contains('${needle ?? ''}');
            if (target is Iterable) return target.contains(needle);
            return false;
          };
        } else {
          value = _lookupProperty(value, name);
        }
      } else if (_match('[')) {
        final key = _ternary();
        _consume(']');
        value = _lookupProperty(value, key);
      } else if (_match('(')) {
        final args = <Object?>[];
        if (!_check(')')) {
          do {
            args.add(_ternary());
          } while (_match(','));
        }
        _consume(')');
        if (value is PugHelper) {
          value = value(args);
        } else {
          throw UnsupportedFeatureException(
              'Only explicit Dart helpers can be called.', span);
        }
      } else {
        return value;
      }
    }
  }

  Object? _primary() {
    if (_match('(')) {
      final value = _ternary();
      _consume(')');
      return value;
    }
    if (_match('[')) {
      final values = <Object?>[];
      if (!_check(']')) {
        do {
          values.add(_ternary());
        } while (_match(','));
      }
      _consume(']');
      return values;
    }
    if (_match('{')) {
      final map = <String, Object?>{};
      if (!_check('}')) {
        do {
          final keyToken = _advance();
          final key = keyToken.literal ?? keyToken.lexeme;
          _consume(':');
          map[key.toString()] = _ternary();
        } while (_match(','));
      }
      _consume('}');
      return map;
    }
    final token = _advance();
    if (token.type == _TokenType.string || token.type == _TokenType.number) {
      return token.literal;
    }
    if (token.type == _TokenType.identifier) {
      switch (token.lexeme) {
        case 'true':
          return true;
        case 'false':
          return false;
        case 'null':
        case 'undefined':
          return null;
      }
      if (helpers.containsKey(token.lexeme)) return helpers[token.lexeme];
      return scope.lookup(token.lexeme);
    }
    throw PugRenderException('Expected expression', span);
  }

  Object? _lookupProperty(Object? target, Object? key) {
    if (target == null) return null;
    if (target is PugHelper) return _lookupProperty(target(const []), key);
    if (key == 'length') {
      if (target is String) return target.length;
      if (target is Iterable) return target.length;
      if (target is Map) return target.length;
    }
    if (target is Map) return target[key] ?? target[key.toString()];
    if (target is List && key is num) return target[key.toInt()];
    if (target is String && key is num) return target[key.toInt()];
    return null;
  }

  num _num(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  int _compare(Object? left, Object? right) {
    if (left is num || right is num) return _num(left).compareTo(_num(right));
    return '${left ?? ''}'.compareTo('${right ?? ''}');
  }

  bool _match(String lexeme) {
    if (_check(lexeme)) {
      index++;
      return true;
    }
    return false;
  }

  bool _matchWord(String word) => _checkIdentifier(word) && index++ >= 0;

  bool _check(String lexeme) => tokens[index].lexeme == lexeme;

  bool _checkIdentifier(String word) =>
      tokens[index].type == _TokenType.identifier &&
      tokens[index].lexeme == word;

  _Token _advance() => tokens[index++];

  void _consume(String lexeme) {
    if (!_match(lexeme)) throw PugRenderException('Expected "$lexeme"', span);
  }

  void _expect(_TokenType type) {
    if (tokens[index].type != type) {
      throw PugRenderException(
          'Unexpected token "${tokens[index].lexeme}"', span);
    }
  }

  String _consumeIdentifier() {
    final token = _advance();
    if (token.type != _TokenType.identifier) {
      throw PugRenderException('Expected identifier', span);
    }
    return token.lexeme;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _Scanner {
  _Scanner(this.source, this.span);

  final String source;
  final PugSourceSpan? span;
  final tokens = <_Token>[];
  int index = 0;

  List<_Token> scan() {
    while (index < source.length) {
      final char = source[index];
      if (char.trim().isEmpty) {
        index++;
      } else if (_isDigit(char)) {
        _number();
      } else if (_isIdentifierStart(char)) {
        _identifier();
      } else if (char == '"' || char == "'") {
        _string(char);
      } else {
        _operator();
      }
    }
    tokens.add(const _Token(_TokenType.eof, '', null));
    return tokens;
  }

  void _number() {
    final start = index;
    while (index < source.length && _isDigit(source[index])) {
      index++;
    }
    if (index < source.length && source[index] == '.') {
      index++;
      while (index < source.length && _isDigit(source[index])) {
        index++;
      }
    }
    final lexeme = source.substring(start, index);
    tokens.add(_Token(_TokenType.number, lexeme, num.parse(lexeme)));
  }

  void _identifier() {
    final start = index;
    while (index < source.length && _isIdentifierPart(source[index])) {
      index++;
    }
    tokens.add(
        _Token(_TokenType.identifier, source.substring(start, index), null));
  }

  void _string(String quote) {
    index++;
    final buffer = StringBuffer();
    while (index < source.length && source[index] != quote) {
      if (source[index] == r'\') {
        index++;
        if (index >= source.length) break;
        final escaped = source[index++];
        buffer.write(switch (escaped) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          _ => escaped,
        });
      } else {
        buffer.write(source[index++]);
      }
    }
    if (index >= source.length) {
      throw PugRenderException('Unterminated string', span);
    }
    index++;
    tokens.add(_Token(_TokenType.string, buffer.toString(), buffer.toString()));
  }

  void _operator() {
    for (final op in ['===', '!==', '&&', '||', '==', '!=', '<=', '>=']) {
      if (source.startsWith(op, index)) {
        tokens.add(_Token(_TokenType.operator, op, null));
        index += op.length;
        return;
      }
    }
    final char = source[index++];
    if ('+-*/%<>()[]{}?:,.!'.contains(char)) {
      tokens.add(_Token(_TokenType.operator, char, null));
      return;
    }
    throw UnsupportedFeatureException(
        'Unsupported expression token "$char"', span);
  }

  bool _isDigit(String char) =>
      char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
  bool _isIdentifierStart(String char) => RegExp(r'[A-Za-z_$]').hasMatch(char);
  bool _isIdentifierPart(String char) => RegExp(r'[\w$-]').hasMatch(char);
}

enum _TokenType { identifier, number, string, operator, eof }

class _Token {
  const _Token(this.type, this.lexeme, this.literal);
  final _TokenType type;
  final String lexeme;
  final Object? literal;
}
