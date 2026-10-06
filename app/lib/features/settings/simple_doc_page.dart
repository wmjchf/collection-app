import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';

/// 简易说明文稿页（协议 / 隐私等）
class SimpleDocPage extends StatelessWidget {
  const SimpleDocPage({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ScreenDwellScope(
      screen: AnalyticsScreens.doc,
      props: {'doc': title},
      child: Scaffold(
      backgroundColor: colors.pageBg,
      appBar: AppBar(
        centerTitle: true,
        leadingWidth: 80,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: colors.ink,
            padding: const EdgeInsets.only(left: 8),
          ),
          icon: const Icon(Icons.chevron_left, size: 30),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text(
              body.trim(),
              style: TextStyle(
                fontSize: 14,
                color: colors.muted,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
