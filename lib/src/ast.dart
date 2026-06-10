import 'diagnostics.dart';

abstract class PugNode {
  const PugNode(this.span);
  final PugSourceSpan span;
}

class PugDocument extends PugNode {
  const PugDocument(super.span, this.children);
  final List<PugNode> children;
}

class DoctypeNode extends PugNode {
  const DoctypeNode(super.span, this.value);
  final String value;
}

class TagNode extends PugNode {
  const TagNode(
    super.span, {
    required this.name,
    required this.id,
    required this.classes,
    required this.attributes,
    required this.attributeSpreads,
    required this.children,
    this.inlineText,
    this.bufferExpression,
    this.unescapedBuffer = false,
    this.textBlock,
    this.selfClosing = false,
  });

  final String name;
  final String? id;
  final List<String> classes;
  final List<PugAttribute> attributes;
  final List<String> attributeSpreads;
  final List<PugNode> children;
  final String? inlineText;
  final String? bufferExpression;
  final bool unescapedBuffer;
  final String? textBlock;
  final bool selfClosing;
}

class PugAttribute {
  const PugAttribute(this.name, this.expression, {this.escaped = true});
  final String name;
  final String? expression;
  final bool escaped;
}

class TextNode extends PugNode {
  const TextNode(super.span, this.text, {this.unescaped = false});
  final String text;
  final bool unescaped;
}

class ExpressionNode extends PugNode {
  const ExpressionNode(super.span, this.expression, {this.unescaped = false});
  final String expression;
  final bool unescaped;
}

class LocalAssignmentNode extends PugNode {
  const LocalAssignmentNode(super.span, this.name, this.expression);
  final String name;
  final String expression;
}

class CommentNode extends PugNode {
  const CommentNode(super.span, this.text,
      {this.buffered = true, this.blockText});
  final String text;
  final bool buffered;
  final String? blockText;
}

class IfNode extends PugNode {
  const IfNode(super.span, this.branches, this.elseChildren);
  final List<IfBranch> branches;
  final List<PugNode>? elseChildren;
}

class IfBranch {
  const IfBranch(this.expression, this.children);
  final String expression;
  final List<PugNode> children;
}

class EachNode extends PugNode {
  const EachNode(
    super.span, {
    required this.valueName,
    required this.keyName,
    required this.iterableExpression,
    required this.children,
    required this.elseChildren,
  });

  final String valueName;
  final String? keyName;
  final String iterableExpression;
  final List<PugNode> children;
  final List<PugNode>? elseChildren;
}

class WhileNode extends PugNode {
  const WhileNode(super.span, this.expression, this.children);
  final String expression;
  final List<PugNode> children;
}

class CaseNode extends PugNode {
  const CaseNode(
      super.span, this.expression, this.branches, this.defaultChildren);
  final String expression;
  final List<CaseBranch> branches;
  final List<PugNode>? defaultChildren;
}

class CaseBranch {
  const CaseBranch(this.expression, this.children);
  final String expression;
  final List<PugNode> children;
}

class IncludeNode extends PugNode {
  const IncludeNode(super.span, this.path);
  final String path;
}

class ExtendsNode extends PugNode {
  const ExtendsNode(super.span, this.path);
  final String path;
}

class BlockNode extends PugNode {
  const BlockNode(super.span, this.name, this.mode, this.children);
  final String name;
  final BlockMode mode;
  final List<PugNode> children;
}

enum BlockMode { replace, append, prepend }

class YieldBlockNode extends PugNode {
  const YieldBlockNode(super.span);
}

class MixinDeclarationNode extends PugNode {
  const MixinDeclarationNode(super.span, this.name, this.params, this.children);
  final String name;
  final List<MixinParam> params;
  final List<PugNode> children;
}

class MixinParam {
  const MixinParam(this.name, this.defaultExpression);
  final String name;
  final String? defaultExpression;
}

class MixinCallNode extends PugNode {
  const MixinCallNode(
    super.span,
    this.name,
    this.arguments,
    this.attributes,
    this.attributeSpreads,
    this.children,
  );

  final String name;
  final List<String> arguments;
  final List<PugAttribute> attributes;
  final List<String> attributeSpreads;
  final List<PugNode> children;
}

class FilterNode extends PugNode {
  const FilterNode(super.span, this.name, this.text, this.attributes);
  final String name;
  final String text;
  final List<PugAttribute> attributes;
}
