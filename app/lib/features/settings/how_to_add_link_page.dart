import 'package:flutter/material.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';

/// 如何添加链接（设置 → 使用帮助）
class HowToAddLinkPage extends StatelessWidget {
  const HowToAddLinkPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    return ScreenDwellScope(
      screen: AnalyticsScreens.howToAddLink,
      child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 80,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: _text,
            padding: const EdgeInsets.only(left: 8),
          ),
          icon: const Icon(Icons.chevron_left, size: 30),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: const Text(
          '如何添加链接',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            '任选一种方式即可把链接存进 ${AppBrand.name}。',
            style: const TextStyle(fontSize: 14, color: _muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _HelpCard(
            title: '系统分享',
            desc:
                '在微信、Safari、B站、抖音等 App 里点「分享」，选择「${AppBrand.name}」即可入库。图标行可左右滑动；若没有，点「编辑」打开开关。',
          ),
          const SizedBox(height: 12),
          _HelpCard(
            title: '复制链接自动保存',
            desc:
                '先在其他 App 复制可用链接，再打开 ${AppBrand.name}（或从后台切回），会自动读取剪贴板并保存。',
          ),
          const SizedBox(height: 12),
          const _HelpCard(
            title: '快捷指令（iOS）',
            desc:
                '复制链接后，可用主屏幕图标、控制中心或「轻点背面」（互不影响，任选）。不必打开 App。设置 → iOS 快捷指令说明里可安装。',
          ),
        ],
      ),
    ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.title, required this.desc});

  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F242E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF737A85),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
