import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/features/items/transcript_display.dart';

/// 单段转写文稿全屏阅读（仅文稿正文，样式与阅读页正文一致）
class ItemTranscriptPage extends StatelessWidget {
  const ItemTranscriptPage({
    super.key,
    required this.text,
  });

  final String text;

  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    final body = text.trim();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AppSubpageAppBar(title: '文稿'),
      body: body.isEmpty
          ? const Center(
              child: Text(
                '暂无文稿',
                style: TextStyle(fontSize: 15, color: _muted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              children: [
                TranscriptDisplay(
                  text: body,
                  bodyStyle: TranscriptDisplay.defaultBodyStyle,
                ),
              ],
            ),
    );
  }
}
