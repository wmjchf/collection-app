import 'package:super_collection/core/config/app_brand.dart';
import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/onboarding/shortcuts_help_page.dart';
import 'package:super_collection/features/settings/account_page.dart';
import 'package:super_collection/features/settings/account_security_page.dart';
import 'package:super_collection/features/settings/ai_auto_tags_help_page.dart';
import 'package:super_collection/features/settings/feedback_page.dart';
import 'package:super_collection/features/settings/how_to_add_link_page.dart';
import 'package:super_collection/features/settings/legal_docs.dart';
import 'package:super_collection/features/settings/logout_confirm_dialog.dart';
import 'package:super_collection/features/settings/settings_list.dart';
import 'package:super_collection/features/settings/simple_doc_page.dart';

/// 设置内容（设置页 / 账户抽屉共用）
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, this.showAccountEntry = true});

  /// 账户抽屉内方案卡已含入口时设为 false
  final bool showAccountEntry;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  static const _version = 'v1.3.8';

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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              if (widget.showAccountEntry) ...[
                SettingsCardGroup(
                  children: [
                    SettingsInfoRow(
                      title: '账户和用量',
                      showChevron: true,
                      onTap: () => _open(const AccountPage()),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              const SettingsSectionLabel('使用帮助'),
              const SizedBox(height: 8),
              SettingsCardGroup(
                children: [
                  SettingsInfoRow(
                    title: '如何添加链接',
                    showChevron: true,
                    onTap: () => _open(const HowToAddLinkPage()),
                  ),
                  SettingsInfoRow(
                    title: 'iOS 快捷指令说明',
                    showChevron: true,
                    onTap: () => _open(const ShortcutsHelpPage()),
                  ),
                  SettingsInfoRow(
                    title: 'AI自动标签分类方法',
                    showChevron: true,
                    onTap: () => _open(const AiAutoTagsHelpPage()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SettingsSectionLabel('关于'),
              const SizedBox(height: 8),
              SettingsCardGroup(
                children: [
                  SettingsInfoRow(
                    title: '意见反馈',
                    showChevron: true,
                    onTap: () => _open(const FeedbackPage()),
                  ),
                  SettingsInfoRow(
                    title: '用户协议',
                    showChevron: true,
                    onTap: () => _open(
                      const SimpleDocPage(
                        title: '用户协议',
                        body: LegalDocs.userAgreement,
                      ),
                    ),
                  ),
                  SettingsInfoRow(
                    title: '隐私政策',
                    showChevron: true,
                    onTap: () => _open(
                      const SimpleDocPage(
                        title: '隐私政策',
                        body: LegalDocs.privacyPolicy,
                      ),
                    ),
                  ),
                  SettingsInfoRow(
                    title: '账号安全',
                    showChevron: true,
                    onTap: () => _open(const AccountSecurityPage()),
                  ),
                  SettingsInfoRow(
                    title: '关于 ${AppBrand.name}',
                    trailing: Text(
                      _version,
                      style: TextStyle(fontSize: 14, color: colors.muted),
                    ),
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
                  backgroundColor: colors.card,
                  foregroundColor: colors.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '退出账户',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.danger,
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
