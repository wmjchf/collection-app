import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/features/items/reading_font_prefs.dart';
import 'package:super_collection/features/items/transcript_display.dart';
import 'package:super_collection/features/items/transcript_models.dart';

/// 单段转写文稿全屏阅读（仅文稿正文，样式与阅读页正文一致）
class ItemTranscriptPage extends StatelessWidget {
  const ItemTranscriptPage({
    super.key,
    required this.text,
    this.cues = const [],
    this.fontSize = ReadingFontPrefs.defaultSize,
  });

  final String text;
  final List<TranscriptCue> cues;
  final double fontSize;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    final body = text.trim();
    final size = ReadingFontPrefs.clamp(fontSize);
    final bodyStyle = TextStyle(
      fontSize: size,
      height: 1.85,
      letterSpacing: 0.2,
      color: _text,
    );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AppSubpageAppBar(title: '文稿'),
      body: body.isEmpty
          ? Center(
              child: Text(
                '暂无文稿',
                style: TextStyle(fontSize: size, color: _muted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              children: [
                TranscriptDisplay(
                  text: body,
                  cues: cues,
                  bodyStyle: bodyStyle,
                ),
              ],
            ),
    );
  }
}
