class PugSourceSpan {
  const PugSourceSpan({
    required this.filename,
    required this.line,
    required this.column,
    required this.sourceLine,
  });

  final String filename;
  final int line;
  final int column;
  final String sourceLine;

  @override
  String toString() => '$filename:$line:$column';
}

class PugException implements Exception {
  PugException(this.message, [this.span]);

  final String message;
  final PugSourceSpan? span;

  @override
  String toString() {
    final source = span;
    if (source == null) {
      return 'PugException: $message';
    }
    return 'PugException: $message at $source\n${source.sourceLine}';
  }
}

class PugParseException extends PugException {
  PugParseException(super.message, [super.span]);
}

class PugRenderException extends PugException {
  PugRenderException(super.message, [super.span]);
}

class PugIOException extends PugException {
  PugIOException(super.message, [super.span]);
}

class UnsupportedFeatureException extends PugException {
  UnsupportedFeatureException(super.message, [super.span]);
}
