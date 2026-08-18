import 'package:flutter/material.dart';
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

    return Scaffold(
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
          icon: const Icon(Icons.chevron_left, size: 28),
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
                ? '点下方按钮一键安装即可，不用在快捷指令里自己搜索、拼接操作。装好后可加到主屏幕，也可绑到「轻点背面」。'
                : '预置安装链接配置后，用户只需点「添加快捷指令」一键安装，无需自己搜索拼接。',
            style: const TextStyle(
              fontSize: 14,
              color: _muted,
              height: 1.4,
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
          const SizedBox(height: 16),
          const _HelpCard(
            title: '安装后怎么用',
            desc:
                '1. 先打开本 App 并登录一次\n'
                '2. 点「添加快捷指令」→ 系统里点「添加」\n'
                '3. 打开「保存链接到Conflux」→ 分享 →「加到主屏幕」\n'
                '之后：复制链接 → 点主屏幕图标（不进 App）',
          ),
          const SizedBox(height: 12),
          const _HelpCard(
            title: '轻点背面（连点两下）',
            desc:
                '用同一条快捷指令，不用另装。iPhone 8 及更新机型：\n'
                '\n'
                '1. 设置 → 辅助功能 → 触控 → 轻点背面\n'
                '2. 选「轻点两下」\n'
                '3. 在快捷指令里选刚添加的「保存链接到Conflux」\n'
                '\n'
                '之后：复制链接 → 在手机背面连点两下即可保存。\n'
                '主屏幕图标可以继续留着，两种方式都能用。',
          ),
        ],
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
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
