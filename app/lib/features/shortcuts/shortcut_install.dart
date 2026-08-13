import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/features/shortcuts/shortcut_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// 设置页主路径：一键添加快捷指令。
/// 有 iCloud 链接则直接打开；否则引导用户用 URL Scheme 手动添加（复制 + 打开快捷指令）。
Future<void> openShortcutInstall(BuildContext context) async {
  final install = ShortcutConfig.installIcloudUrl.trim();
  if (install.isNotEmpty) {
    final uri = Uri.tryParse(install);
    if (uri != null && await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ManualInstallSheet(),
  );
}

class _ManualInstallSheet extends StatelessWidget {
  const _ManualInstallSheet();

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _fieldBg = Color(0xFFF5F7FA);

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(
      const ClipboardData(text: ShortcutConfig.saveClipboardUri),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制打开链接')),
    );
  }

  Future<void> _openShortcutsApp(BuildContext context) async {
    final uri = Uri.parse('shortcuts://');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开「快捷指令」，请手动打开该 App')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD9DBE0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '添加「从剪贴板保存」',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '正式预置安装链接发布前，可按下面 3 步添加（约半分钟）。',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          const _Step(index: '1', text: '复制下方打开链接'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _fieldBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              ShortcutConfig.saveClipboardUri,
              style: TextStyle(
                fontSize: 14,
                color: _text,
                fontFamily: 'Courier',
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _copy(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: const BorderSide(color: _blue),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('复制链接'),
          ),
          const SizedBox(height: 16),
          const _Step(
            index: '2',
            text: '打开「快捷指令」→ 新建 → 添加操作「打开 URL」→ 粘贴刚复制的链接 → 完成',
          ),
          const SizedBox(height: 12),
          const _Step(
            index: '3',
            text: '右上角分享 →「加到主屏幕」，之后复制链接点图标即可保存',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => _openShortcutsApp(context),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('打开「快捷指令」'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFE8F0FF),
            shape: BoxShape.circle,
          ),
          child: Text(
            index,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2F6FED),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1F242E),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
