import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/onboarding/shortcuts_help_page.dart';
import 'package:super_collection/features/settings/ai_agent_help_page.dart';
import 'package:super_collection/features/settings/ai_auto_tags_help_page.dart';
import 'package:super_collection/features/settings/how_to_add_link_page.dart';
import 'package:super_collection/features/settings/settings_modal.dart';

/// 使用帮助目录（一级设置只留本入口）
class HelpHubPage extends StatelessWidget {
  const HelpHubPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);

  void _open(BuildContext context, Widget page) {
    openSettingsPage<void>(context, page);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenDwellScope(
      screen: AnalyticsScreens.settings,
      props: const {'page': 'help_hub'},
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leadingWidth: SettingsBackButton.leadingWidth,
          leading: const SettingsBackButton(),
          title: const Text(
            '使用帮助',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _CardGroup(
              children: [
                _NavRow(
                  title: '如何添加链接',
                  onTap: () => _open(context, const HowToAddLinkPage()),
                ),
                _NavRow(
                  title: 'AI助手',
                  onTap: () => _open(context, const AiAgentHelpPage()),
                ),
                _NavRow(
                  title: 'AI自动标签方法',
                  onTap: () => _open(context, const AiAutoTagsHelpPage()),
                ),
                _NavRow(
                  title: 'iOS 快捷指令说明',
                  onTap: () => _open(context, const ShortcutsHelpPage()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardGroup extends StatelessWidget {
  const _CardGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, color: Color(0xFF1F242E)),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 22,
              color: Color(0xFF737A85),
            ),
          ],
        ),
      ),
    );
  }
}
