import 'package:flutter/material.dart';

/// 解析并渲染带「说话人 N：」前缀的转写文稿
class TranscriptDisplay extends StatelessWidget {
  const TranscriptDisplay({
    super.key,
    required this.text,
    this.bodyStyle,
    this.selectable = true,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? bodyStyle;
  final bool selectable;
  final int? maxLines;
  final TextOverflow? overflow;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  static const defaultBodyStyle = TextStyle(
    fontSize: 15,
    height: 1.85,
    letterSpacing: 0.2,
    color: _text,
  );

  static final _speakerPrefix = RegExp(r'^说话人 (\d+)：(.*)$', dotAll: true);

  static List<_TranscriptBlock> parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    final parts = trimmed.split(RegExp(r'\n{2,}'));
    final blocks = <_TranscriptBlock>[];
    for (final part in parts) {
      final chunk = part.trim();
      if (chunk.isEmpty) continue;
      final match = _speakerPrefix.firstMatch(chunk);
      if (match != null) {
        blocks.add(
          _TranscriptBlock(
            speaker: int.tryParse(match.group(1)!),
            body: match.group(2)!.trim(),
          ),
        );
      } else {
        blocks.add(_TranscriptBlock(body: chunk));
      }
    }
    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    final style = bodyStyle ?? defaultBodyStyle;
    final blocks = parse(text);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final hasSpeakers = blocks.any((b) => b.speaker != null);
    if (!hasSpeakers) {
      return _textWidget(text.trim(), style);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 18),
          _SpeakerBlock(
            block: blocks[i],
            bodyStyle: style,
            selectable: selectable,
            maxLines: maxLines,
            overflow: overflow,
          ),
        ],
      ],
    );
  }

  Widget _textWidget(
    String value,
    TextStyle style, {
    int? maxLines,
    TextOverflow? overflow,
  }) {
    if (selectable) {
      return SelectableText(
        value,
        style: style,
        maxLines: maxLines,
      );
    }
    return Text(
      value,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

class _TranscriptBlock {
  const _TranscriptBlock({this.speaker, required this.body});

  final int? speaker;
  final String body;
}

class _SpeakerBlock extends StatelessWidget {
  const _SpeakerBlock({
    required this.block,
    required this.bodyStyle,
    required this.selectable,
    this.maxLines,
    this.overflow,
  });

  final _TranscriptBlock block;
  final TextStyle bodyStyle;
  final bool selectable;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final speaker = block.speaker;
    final body = block.body;
    if (speaker == null) {
      return selectable
          ? SelectableText(body, style: bodyStyle, maxLines: maxLines)
          : Text(body, style: bodyStyle, maxLines: maxLines, overflow: overflow);
    }

    final labelStyle = bodyStyle.copyWith(
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: TranscriptDisplay._muted,
      letterSpacing: 0.1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('说话人 $speaker：', style: labelStyle),
        const SizedBox(height: 6),
        selectable
            ? SelectableText(body, style: bodyStyle, maxLines: maxLines)
            : Text(
                body,
                style: bodyStyle,
                maxLines: maxLines,
                overflow: overflow,
              ),
      ],
    );
  }
}
