import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/onboarding/onboarding_prefs.dart';
import 'package:super_collection/features/onboarding/shortcuts_help_page.dart';
import 'package:super_collection/features/settings/delete_account_confirm_dialog.dart';
import 'package:super_collection/features/settings/how_to_add_link_page.dart';
import 'package:super_collection/features/settings/legal_docs.dart';
import 'package:super_collection/features/settings/logout_confirm_dialog.dart';
import 'package:super_collection/features/settings/simple_doc_page.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 设置内容（设置页 / 账户抽屉共用）
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _version = 'v1.0.0';

  final _auth = AuthRepository();
  final _usageRepo = UsageRepository();
  AuthSession? _session;
  UsageSummary? _usage;
  bool _loading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    UsageRefresh.version.addListener(_onUsageRefresh);
    _load();
  }

  @override
  void dispose() {
    UsageRefresh.version.removeListener(_onUsageRefresh);
    super.dispose();
  }

  void _onUsageRefresh() => _load();

  Future<void> _load() async {
    final session = await _auth.readSession();
    UsageSummary? usage;
    try {
      usage = await _usageRepo.fetchUsage();
    } catch (_) {
      usage = null;
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _usage = usage;
      _loading = false;
    });
  }

  String _fmtMinutes(double m) {
    if (m == m.roundToDouble()) return m.toInt().toString();
    return m.toStringAsFixed(1);
  }

  String _maskedPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '—';
    final digits = phone.split('').where((c) {
      final code = c.codeUnitAt(0);
      return code >= 48 && code <= 57;
    }).join();
    if (digits.length >= 7) {
      return '${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
    }
    return phone;
  }

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

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final ok = await showDeleteAccountConfirmDialog(context);
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final userId = _session?.userId;
    try {
      await _auth.deleteAccount();
      if (userId != null) {
        await OnboardingPrefs.clear(userId: userId);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppToast.show(context, '注销失败，请稍后重试');
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              const _SectionLabel('账号'),
              const SizedBox(height: 8),
              _CardGroup(
                children: [
                  _InfoRow(
                    title: '手机号',
                    trailing: Text(
                      _maskedPhone(_session?.phone),
                      style: const TextStyle(fontSize: 14, color: _muted),
                    ),
                  ),
                ],
              ),
              if (_usage != null) ...[
                const SizedBox(height: 16),
                _SectionLabel(
                  _usage!.yearMonth.isEmpty
                      ? '本月用量'
                      : '本月用量（${_usage!.yearMonth}）',
                ),
                const SizedBox(height: 8),
                _CardGroup(
                  children: [
                    _InfoRow(
                      title: '转写',
                      trailing: Text(
                        '${_fmtMinutes(_usage!.transcriptUsedMinutes)} / ${_fmtMinutes(_usage!.transcriptLimitMinutes)} 分钟',
                        style: const TextStyle(fontSize: 14, color: _muted),
                      ),
                    ),
                    _InfoRow(
                      title: 'AI',
                      trailing: Text(
                        '${formatTokenCount(_usage!.aiUsedTokens)} / ${formatTokenCount(_usage!.aiLimitTokens)} token',
                        style: const TextStyle(fontSize: 14, color: _muted),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const _SectionLabel('使用帮助'),
              const SizedBox(height: 8),
              _CardGroup(
                children: [
                  _InfoRow(
                    title: 'iOS 快捷指令说明',
                    showChevron: true,
                    onTap: () => _open(const ShortcutsHelpPage()),
                  ),
                  _InfoRow(
                    title: '如何添加链接',
                    showChevron: true,
                    onTap: () => _open(const HowToAddLinkPage()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('关于'),
              const SizedBox(height: 8),
              _CardGroup(
                children: [
                  _InfoRow(
                    title: '用户协议',
                    showChevron: true,
                    onTap: () => _open(
                      const SimpleDocPage(
                        title: '用户协议',
                        body: LegalDocs.userAgreement,
                      ),
                    ),
                  ),
                  _InfoRow(
                    title: '隐私政策',
                    showChevron: true,
                    onTap: () => _open(
                      const SimpleDocPage(
                        title: '隐私政策',
                        body: LegalDocs.privacyPolicy,
                      ),
                    ),
                  ),
                  const _InfoRow(
                    title: '关于 Conflux',
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
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                SizedBox(
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
                TextButton(
                  onPressed: _deleting ? null : _deleteAccount,
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    minimumSize: const Size(double.infinity, 36),
                  ),
                  child: Text(
                    _deleting ? '注销中…' : '注销账户',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    this.trailing,
    this.showChevron = false,
    this.onTap,
  });

  final String title;
  final Widget? trailing;
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
            if (trailing != null) trailing!,
            if (showChevron)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF737A85),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
