import 'package:flutter/material.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/features/onboarding/onboarding_prefs.dart';
import 'package:super_collection/features/onboarding/shortcuts_help_page.dart';
import 'package:super_collection/features/shell/main_shell.dart';
import 'package:super_collection/features/shortcuts/shortcut_inbound.dart';

/// 首次引导（对齐 Figma `22. 首次引导`）
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, this.userId});

  final int? userId;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  Future<void> _start(BuildContext context) async {
    await OnboardingPrefs.markSeen(userId: userId);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShortcutInbound.flushPending();
    });
  }

  void _openShortcutsHelp(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ShortcutsHelpPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                AppBrand.name,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '把好内容收到一处，想看的时候翻得出来。',
                style: TextStyle(
                  fontSize: 15,
                  color: _muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                '三种收藏方式（任选）',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 12),
              const _WayCard(
                title: '系统分享',
                desc:
                    '在微信、Safari、抖音等 App 点「分享」，选择「${AppBrand.name}」即可保存',
              ),
              const SizedBox(height: 10),
              const _WayCard(
                title: '复制链接',
                desc: '在其他 App 复制可用链接后打开本 App，会自动读取剪贴板并保存',
              ),
              const SizedBox(height: 10),
              const _WayCard(
                title: '快捷指令',
                desc: 'iOS 可加到主屏幕、控制中心或「轻点背面」，互不影响：复制链接后点一下即可保存',
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () => _start(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '开始使用',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _openShortcutsHelp(context),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '查看 iOS 快捷指令说明',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _blue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WayCard extends StatelessWidget {
  const _WayCard({required this.title, required this.desc});

  final String title;
  final String desc;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _card = Color(0xFFF5F7FA);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
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
