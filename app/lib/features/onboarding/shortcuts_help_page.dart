import 'package:flutter/material.dart';
import 'package:super_collection/features/shortcuts/shortcut_config.dart';
import 'package:super_collection/features/shortcuts/shortcut_install.dart';

/// iOS 快捷指令说明（对齐 Figma `23. 快捷指令说明`）
/// 主路径：一键「添加快捷指令」
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
          const Text(
            '推荐：用系统「App 快捷指令」后台保存，桌面点一下即可，不必打开 App。',
            style: TextStyle(
              fontSize: 14,
              color: _muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          const _HelpCard(
            title: '后台保存（推荐）',
            desc:
                '1. 先打开本 App 并登录一次\n'
                '2. 打开系统「快捷指令」→「+」新建\n'
                '3. 添加操作「获取剪贴板」\n'
                '4. 再添加「保存剪贴板链接」（搜索超级收藏夹），把上一步的剪贴板内容填到「链接」参数\n'
                '5. 完成 → 分享 →「加到主屏幕」\n'
                '之后：复制链接 → 点主屏幕图标即可（不打开 App）。\n'
                '注意：不要只加「保存剪贴板链接」一步——后台直接读剪贴板常被系统拦掉。',
          ),
          const SizedBox(height: 12),
          const _HelpCard(
            title: '说明',
            desc:
                '后台保存依赖登录态（约 7 天有效，过期请重新打开 App 登录）。'
                '微信等需手机抓页的站点，后台只能先入库；下次打开或回到 App 时，会自动排队补齐正文，多条也不用手动选。',
          ),
          const SizedBox(height: 24),
          const Text(
            '旧版安装（会打开 App）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () => openShortcutInstall(context),
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '添加旧版快捷指令',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasOneTap
                ? '旧版会打开超级收藏夹再保存；能用上面「后台保存」就优先用后台。'
                : '点上方按钮按提示添加（会打开 App）。',
            style: const TextStyle(fontSize: 12, color: _muted, height: 1.35),
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
