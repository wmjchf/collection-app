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

/// 设置页（对齐 Figma `24. 设置`）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _version = 'v1.0.0';

  final _auth = AuthRepository();
  AuthSession? _session;
  bool _loading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await _auth.readSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
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
          '设置',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
                    _InfoRow(
                      title: '退出登录',
                      titleColor: const Color(0xFFD14343),
                      onTap: _logout,
                    ),
                    _InfoRow(
                      title: '注销账号',
                      titleColor: const Color(0xFFD14343),
                      onTap: _deleting ? null : _deleteAccount,
                    ),
                  ],
                ),
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
    this.titleColor,
    this.showChevron = false,
    this.onTap,
  });

  final String title;
  final Widget? trailing;
  final Color? titleColor;
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
                style: TextStyle(
                  fontSize: 15,
                  color: titleColor ?? const Color(0xFF1F242E),
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
