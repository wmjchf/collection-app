import 'package:flutter/material.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/settings/about_hub_page.dart';
import 'package:super_collection/features/settings/account_page.dart';
import 'package:super_collection/features/settings/feedback_page.dart';
import 'package:super_collection/features/settings/help_hub_page.dart';
import 'package:super_collection/features/settings/home_modules_settings_page.dart';
import 'package:super_collection/features/settings/logout_confirm_dialog.dart';
import 'package:super_collection/features/settings/settings_modal.dart';

/// 设置内容（设置页 / 账户抽屉共用）
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, this.showAccountEntry = true});

  /// 账户抽屉内方案卡已含入口时设为 false
  final bool showAccountEntry;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final _auth = AuthRepository();

  Future<void> _logout() async {
    final ok = await showLogoutConfirmDialog(context);
    if (ok != true || !mounted) return;
    await _auth.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _open(Widget page) {
    openSettingsPage<void>(context, page);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              if (widget.showAccountEntry) ...[
                _CardGroup(
                  children: [
                    _SettingsRow(
                      title: '账户和用量',
                      showChevron: true,
                      onTap: () => _open(const AccountPage()),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              const _SectionLabel('偏好'),
              const SizedBox(height: 8),
              _CardGroup(
                children: [
                  _SettingsRow(
                    title: '首页模块',
                    showChevron: true,
                    onTap: () => _open(const HomeModulesSettingsPage()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('支持'),
              const SizedBox(height: 8),
              _CardGroup(
                children: [
                  _SettingsRow(
                    title: '使用帮助',
                    showChevron: true,
                    onTap: () => _open(const HelpHubPage()),
                  ),
                  _SettingsRow(
                    title: '意见反馈',
                    showChevron: true,
                    onTap: () => _open(const FeedbackPage()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('关于'),
              const SizedBox(height: 8),
              _CardGroup(
                children: [
                  _SettingsRow(
                    title: '关于 ${AppBrand.name}',
                    showChevron: true,
                    onTap: () => _open(const AboutHubPage()),
                  ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: _logout,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFD14343),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '退出账户',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD14343),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFF737A85),
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

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.showChevron = false,
    this.onTap,
  });

  final String title;
  final bool showChevron;
  final VoidCallback? onTap;

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
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF1F242E),
                ),
              ),
            ),
            if (showChevron)
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
      ),
    );
  }
}
