import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/onboarding/onboarding_prefs.dart';
import 'package:super_collection/features/settings/delete_account_confirm_dialog.dart';

/// 账号安全页：设置外层不出现「注销」字样，注销操作仅在此页内。
class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key});

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage>
    with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _danger = Color(0xFFD14343);

  final _auth = AuthRepository();
  bool _deleting = false;

  @override
  String get dwellScreen => AnalyticsScreens.accountSecurity;

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final ok = await showDeleteAccountConfirmDialog(context);
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final session = await _auth.readSession();
    final userId = session?.userId;
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
      AppToast.show(context, '操作失败，请稍后重试');
    }
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
          icon: const Icon(Icons.chevron_left, size: 30),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: const Text(
          '账号安全',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '危险操作',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '永久删除当前账号及全部数据（收藏、标注、转写与 AI 相关数据等），且无法恢复。同一手机号之后可重新注册。\n\n若仅换设备使用，返回上一页选择「退出账户」即可。',
              style: TextStyle(fontSize: 14, color: _muted, height: 1.65),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: _deleting ? null : _deleteAccount,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _danger,
                disabledForegroundColor: _danger.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _deleting ? '处理中…' : '注销账户',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
