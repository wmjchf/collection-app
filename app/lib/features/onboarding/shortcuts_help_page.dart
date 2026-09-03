import 'package:flutter/material.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/shortcuts/shortcut_config.dart';
import 'package:super_collection/features/shortcuts/shortcut_install.dart';

/// iOS 快捷指令说明：一键安装预置指令（不打开 App）。
class ShortcutsHelpPage extends StatelessWidget {
  const ShortcutsHelpPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    final hasOneTap = ShortcutConfig.installIcloudUrl.trim().isNotEmpty;

    return ScreenDwellScope(
      screen: AnalyticsScreens.shortcutsHelp,
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
          '快捷指令',
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
            hasOneTap
                ? '先安装「${AppBrand.shortcutInstallName}」。主屏幕、控制中心、轻点背面互不影响，装好后任选，也可一起开。'
                : '预置安装链接配置后，用户只需点「添加快捷指令」一键安装，无需自己搜索拼接。',
            style: const TextStyle(
              fontSize: 14,
              color: _muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: hasOneTap
                  ? () => openShortcutInstall(context)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                disabledBackgroundColor: const Color(0xFFB8C4D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '添加快捷指令',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (!hasOneTap) ...[
            const SizedBox(height: 8),
            const Text(
              '开发者尚未配置 iCloud 预置链接，按钮暂不可用。',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.35),
            ),
          ],
          const SizedBox(height: 28),
          const _SectionLabel(text: '只需一次'),
          const SizedBox(height: 10),
          const _HelpCard(
            title: '添加指令',
            desc:
                '先打开本 App 并登录，再点上方按钮，在系统页点「添加」。\n'
                '装好后即可分别设置下面的用法，不必按顺序做完。',
          ),
          const SizedBox(height: 28),
          const _SectionLabel(text: '用法互不影响，任选'),
          const SizedBox(height: 10),
          const _HelpCard(
            title: '加到主屏幕',
            desc:
                '打开「${AppBrand.shortcutInstallName}」→ 分享 →「加到主屏幕」。\n'
                '之后：复制链接 → 点主屏幕图标。',
          ),
          const SizedBox(height: 10),
          const _HelpCard(
            title: '加到控制中心',
            desc:
                'iOS 18 及更新：打开控制中心 → 点左上角「+」→「添加控件」→ 搜「快捷指令」→ 选「${AppBrand.shortcutInstallName}」。\n'
                '之后：复制链接 → 从右上角下滑，点该控件。',
          ),
          const SizedBox(height: 10),
          const _HelpCard(
            title: '轻点背面',
            desc:
                'iPhone 8 及更新：设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下，选「${AppBrand.shortcutInstallName}」。\n'
                '之后：复制链接 → 在手机背面连点两下。',
          ),
        ],
      ),
    ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF737A85),
        letterSpacing: 0.2,
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.title, required this.desc});

  final String title;
  final String desc;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

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
              color: _text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 13,
              color: _muted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
