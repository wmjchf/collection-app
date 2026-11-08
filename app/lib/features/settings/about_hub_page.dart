import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/features/settings/legal_docs.dart';
import 'package:super_collection/features/settings/settings_modal.dart';
import 'package:super_collection/features/settings/simple_doc_page.dart';

/// 关于目录：协议 / 隐私 / 版本
class AboutHubPage extends StatelessWidget {
  const AboutHubPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _version = 'v1.7.5';

  void _open(BuildContext context, Widget page) {
    openSettingsPage<void>(context, page);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenDwellScope(
      screen: AnalyticsScreens.settings,
      props: const {'page': 'about_hub'},
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leadingWidth: SettingsBackButton.leadingWidth,
          leading: const SettingsBackButton(),
          title: Text(
            '关于 ${AppBrand.name}',
            style: const TextStyle(
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
                  title: '用户协议',
                  onTap: () => _open(
                    context,
                    const SimpleDocPage(
                      title: '用户协议',
                      body: LegalDocs.userAgreement,
                    ),
                  ),
                ),
                _NavRow(
                  title: '隐私政策',
                  onTap: () => _open(
                    context,
                    const SimpleDocPage(
                      title: '隐私政策',
                      body: LegalDocs.privacyPolicy,
                    ),
                  ),
                ),
                const _NavRow(
                  title: '版本',
                  trailing: Text(
                    _version,
                    style: TextStyle(fontSize: 14, color: _muted),
                  ),
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
  const _NavRow({
    required this.title,
    this.trailing,
    this.onTap,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, color: Color(0xFF1F242E)),
            ),
          ),
          if (trailing != null) trailing!,
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right,
                size: 22,
                color: Color(0xFF737A85),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
