import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 中文没有词间空格，系统 justify 拉不齐右边。
/// 按行把多出的宽度摊到字距上，段末行保持左齐。
/// 字距按实际排版宽度收回，避免行末被裁掉。
class JustifiedText extends StatelessWidget {
  const JustifiedText({
    super.key,
    required this.text,
    required this.style,
    this.trailing,
  });

  final String text;
  final TextStyle style;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _justifyLines(
          text,
          style,
          constraints.maxWidth,
          direction: direction,
          textScaler: scaler,
          locale: locale,
        );
        return SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < layout.lines.length; i++)
                if (trailing != null &&
                    layout.tail.isEmpty &&
                    i == layout.lines.length - 1)
                  _withTrailing(_lineText(layout.lines[i], style), trailing!)
                else
                  _lineText(layout.lines[i], style),
              if (layout.tail.isNotEmpty)
                _withTrailing(
                  Text(layout.tail, style: style),
                  trailing,
                ),
            ],
          ),
        );
      },
    );
  }
}

Widget _withTrailing(Widget child, Widget? trailing) {
  if (trailing == null) return child;
  return Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [child, trailing],
  );
}

Widget _lineText(_JustifyLine line, TextStyle style) {
  return Text(
    line.text.isEmpty ? ' ' : line.text,
    maxLines: 1,
    softWrap: false,
    style: line.spacing == 0
        ? style
        : style.copyWith(letterSpacing: line.spacing),
  );
}

class JustifiedLine {
  const JustifiedLine(this.text, this.spacing);
  final String text;
  final double spacing;
}

/// 按给定宽度拆行并计算字距。段末与硬换行不加字距。
List<JustifiedLine> layoutJustifiedLines(
  String text,
  TextStyle style,
  double maxWidth,
) {
  final layout = _justifyLines(
    text,
    style,
    maxWidth,
    direction: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    locale: null,
  );
  return [
    for (final line in layout.lines) JustifiedLine(line.text, line.spacing),
    if (layout.tail.isNotEmpty) JustifiedLine(layout.tail, 0),
  ];
}

class _JustifyLine {
  const _JustifyLine(this.text, this.spacing);
  final String text;
  final double spacing;
}

class _JustifyLayout {
  const _JustifyLayout(this.lines, this.tail);
  final List<_JustifyLine> lines;
  final String tail;
}

_JustifyLayout _justifyLines(
  String text,
  TextStyle style,
  double maxWidth, {
  required TextDirection direction,
  required TextScaler textScaler,
  required Locale? locale,
}) {
  if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
    return _JustifyLayout(const [_JustifyLine('', 0)], '');
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: textScaler,
    locale: locale,
  )..layout(maxWidth: maxWidth);
  final lines = <_JustifyLine>[];
  var offset = 0;
  while (offset < text.length) {
    final range = painter.getLineBoundary(
      TextPosition(offset: offset, affinity: TextAffinity.downstream),
    );
    var end = range.end;
    if (end <= offset) break;
    final start = math.max(range.start, offset);
    final raw = text.substring(start, end);
    final nextIsBreak = end < text.length &&
        (text.codeUnitAt(end) == 0x0A || text.codeUnitAt(end) == 0x0D);
    final hard = raw.endsWith('\n') || nextIsBreak;
    final line = hard ? raw.replaceAll(RegExp(r'[\n\r]+$'), '') : raw;
    final isLast = end >= text.length;
    final spacing = hard || isLast
        ? 0.0
        : _justifySpacing(
            line,
            style,
            maxWidth,
            direction: direction,
            textScaler: textScaler,
            locale: locale,
          );
    lines.add(_JustifyLine(line, spacing));
    offset = end;
  }
  painter.dispose();
  final tail = offset < text.length ? text.substring(offset) : '';
  if (lines.isEmpty) {
    return _JustifyLayout(const [], text);
  }
  return _JustifyLayout(lines, tail);
}

double _measure(
  String line,
  TextStyle style, {
  required TextDirection direction,
  required TextScaler textScaler,
  required Locale? locale,
}) {
  final painter = TextPainter(
    text: TextSpan(text: line, style: style),
    textDirection: direction,
    textScaler: textScaler,
    locale: locale,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

double _justifySpacing(
  String line,
  TextStyle style,
  double maxWidth, {
  required TextDirection direction,
  required TextScaler textScaler,
  required Locale? locale,
}) {
  final count = line.characters.length;
  if (count <= 1) return 0;
  final natural = _measure(
    line,
    style,
    direction: direction,
    textScaler: textScaler,
    locale: locale,
  );
  // 留出半像素，避免取整后仍超出被裁。
  final budget = maxWidth - 0.5;
  final extra = budget - natural;
  if (extra <= 0.5) return 0;
  // 段末行会空出远超一个字的宽度。只拉开「差一点才换行」的行，避免把段末几个字拉开。
  final em = textScaler.scale(style.fontSize ?? 15);
  if (extra > em) return 0;

  double widthOf(double spacing) {
    return _measure(
      line,
      style.copyWith(letterSpacing: spacing),
      direction: direction,
      textScaler: textScaler,
      locale: locale,
    );
  }

  // letterSpacing 加在每个字后面（含行末）时，按字数分才不会超宽。
  var spacing = extra / count;
  var width = widthOf(spacing);
  // 若只加在字与字之间，上面会偏窄，再收到贴齐右边。
  if (budget - width > 1) {
    spacing = extra / (count - 1);
    width = widthOf(spacing);
  }
  if (width > budget && spacing > 0) {
    final added = width - natural;
    if (added <= 0) return 0;
    spacing = spacing * (extra / added);
    width = widthOf(spacing);
  }
  if (width > budget) return 0;
  return spacing;
}
