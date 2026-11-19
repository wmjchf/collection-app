import 'package:flutter/material.dart';
import 'package:super_collection/features/items/transcript_models.dart';

/// 解析并渲染带「说话人 N：」前缀的转写文稿；优先使用结构化 cues（含时间点）
class TranscriptDisplay extends StatelessWidget {
  const TranscriptDisplay({
    super.key,
    required this.text,
    this.cues = const [],
    this.bodyStyle,
    this.selectable = true,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final List<TranscriptCue> cues;
  final TextStyle? bodyStyle;
  final bool selectable;
  final int? maxLines;
  final TextOverflow? overflow;

  static const _text = Color(0xFF2A3038);
  static const _muted = Color(0xFF737A85);

  static const defaultBodyStyle = TextStyle(
    fontSize: 16,
    height: 2.0,
    letterSpacing: 0.15,
    color: _text,
  );

  static final _speakerPrefix = RegExp(r'^说话人 (\d+)：(.*)$', dotAll: true);
  static final _missingSpaceAfterPunct = RegExp(
    r'([.!?。！？])([A-Za-z\u4e00-\u9fff])',
  );
  static final _sentenceChunk = RegExp(
    r'[^.!?。！？]+[.!?。！？]+["\u201d\u2019]?|[^.!?。！？]+$',
  );

  /// 展示/复制用润色：句号后补空格；无段落时按句软分成段（不改库内原文）
  static String polishForReading(String raw) {
    var t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (t.isEmpty) return t;
    t = polishSpaces(t);
    if (RegExp(r'\n\s*\n').hasMatch(t)) return t;

    final sentences = _splitSentences(t);
    if (sentences.length <= 2) return t;

    final paras = <String>[];
    for (var i = 0; i < sentences.length; i += 2) {
      final end = i + 2 <= sentences.length ? i + 2 : sentences.length;
      paras.add(_joinSentences(sentences.sublist(i, end)));
    }
    return paras.where((p) => p.isNotEmpty).join('\n\n');
  }

  /// 仅补句号后空格（短 cue / 说话人块用）
  static String polishSpaces(String raw) {
    return raw.replaceAllMapped(
      _missingSpaceAfterPunct,
      (m) => '${m[1]} ${m[2]}',
    );
  }

  static List<String> _splitSentences(String t) {
    final out = <String>[];
    for (final m in _sentenceChunk.allMatches(t)) {
      final s = m.group(0)!.trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out.isEmpty ? [t] : out;
  }

  static String _joinSentences(List<String> parts) {
    if (parts.isEmpty) return '';
    final buf = StringBuffer(parts.first);
    for (var i = 1; i < parts.length; i++) {
      final prev = parts[i - 1].trimRight();
      if (RegExp(r'[.!?]$').hasMatch(prev)) {
        buf.write(' ');
      }
      buf.write(parts[i]);
    }
    return buf.toString().trim();
  }

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

  static List<_TranscriptBlock> blocksFromCues(List<TranscriptCue> cues) {
    return [
      for (final cue in cues)
        if (cue.text.trim().isNotEmpty)
          _TranscriptBlock(
            speaker: cue.speaker,
            body: polishSpaces(cue.text.trim()),
            startMs: cue.startMs,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final style = bodyStyle ?? defaultBodyStyle;
    final blocks = cues.isNotEmpty
        ? blocksFromCues(cues)
        : parse(polishForReading(text));
    if (blocks.isEmpty) return const SizedBox.shrink();

    final hasSpeakers = blocks.any((b) => b.speaker != null);
    final hasTimes = blocks.any((b) => b.startMs != null);

    if (!hasSpeakers && !hasTimes) {
      if (blocks.length == 1) {
        return _textWidget(blocks.first.body, style);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _textWidget(blocks[i].body, style),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          _SpeakerBlock(
            block: blocks[i],
            bodyStyle: style,
            selectable: selectable,
            maxLines: maxLines,
            overflow: overflow,
            showSpeaker: hasSpeakers,
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
  const _TranscriptBlock({
    this.speaker,
    required this.body,
    this.startMs,
  });

  final int? speaker;
  final String body;
  final int? startMs;
}

class _SpeakerBlock extends StatelessWidget {
  const _SpeakerBlock({
    required this.block,
    required this.bodyStyle,
    required this.selectable,
    required this.showSpeaker,
    this.maxLines,
    this.overflow,
  });

  final _TranscriptBlock block;
  final TextStyle bodyStyle;
  final bool selectable;
  final bool showSpeaker;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final speaker = block.speaker;
    final body = block.body;
    final timeLabel = TranscriptCue.formatTime(block.startMs);

    final labelStyle = bodyStyle.copyWith(
      fontSize: ((bodyStyle.fontSize ?? 15) - 2).clamp(12, 15),
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF3D5A80),
      letterSpacing: 0.15,
    );
    final timeStyle = bodyStyle.copyWith(
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w500,
      color: TranscriptDisplay._muted.withValues(alpha: 0.9),
      letterSpacing: 0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final headerParts = <Widget>[];
    if (timeLabel.isNotEmpty) {
      headerParts.add(Text(timeLabel, style: timeStyle));
    }
    if (showSpeaker && speaker != null) {
      if (headerParts.isNotEmpty) headerParts.add(const SizedBox(width: 8));
      headerParts.add(Text('说话人 $speaker：', style: labelStyle));
    }

    if (headerParts.isEmpty) {
      return selectable
          ? SelectableText(body, style: bodyStyle, maxLines: maxLines)
          : Text(body, style: bodyStyle, maxLines: maxLines, overflow: overflow);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: headerParts,
        ),
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
