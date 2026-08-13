import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/shell/main_shell.dart';

/// 登录页（对齐 Figma：手机号 + 验证码）
/// 开发阶段后端写死验证码，默认 123456。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _placeholder = Color(0xFFB2B8BF);
  static const _border = Color(0xFFD1D6DE);
  static const _blue = Color(0xFF2F6FED);
  static const _blueSoft = Color(0xFFE8F0FF);

  late final AuthRepository _auth =
      widget.authRepository ?? AuthRepository();

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _sending = false;
  bool _loggingIn = false;
  int _countdown = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool _isValidPhone(String phone) => RegExp(r'^1\d{10}$').hasMatch(phone);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onSendCode() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone)) {
      _toast('请输入正确的手机号');
      return;
    }
    if (_sending || _countdown > 0) return;

    setState(() => _sending = true);
    try {
      final message = await _auth.sendCode(phone);
      _toast(message);
      _startCountdown();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('发送失败，请检查网络或后端是否启动');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      if (_countdown <= 1) {
        setState(() => _countdown = 0);
        return false;
      }
      setState(() => _countdown -= 1);
      return true;
    });
  }

  Future<void> _onLogin() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (!_isValidPhone(phone)) {
      _toast('请输入正确的手机号');
      return;
    }
    if (code.isEmpty) {
      _toast('请输入验证码');
      return;
    }
    if (_loggingIn) return;

    setState(() => _loggingIn = true);
    try {
      await _auth.login(phone: phone, code: code);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('登录失败，请检查网络或后端是否启动');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _placeholder, fontSize: 16),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !_sending && _countdown == 0;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '超级收藏夹',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '手机号验证码登录',
                style: TextStyle(fontSize: 16, color: _muted),
              ),
              const SizedBox(height: 32),
              const Text(
                '手机号',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 16, color: _text),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: _fieldDecoration('请输入手机号'),
              ),
              const SizedBox(height: 16),
              const Text(
                '验证码',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 16, color: _text),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: _fieldDecoration('请输入验证码'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    height: 52,
                    child: TextButton(
                      onPressed: canSend ? _onSendCode : null,
                      style: TextButton.styleFrom(
                        backgroundColor: _blueSoft,
                        disabledBackgroundColor: _blueSoft.withValues(
                          alpha: 0.6,
                        ),
                        foregroundColor: _blue,
                        disabledForegroundColor: _blue.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _countdown > 0 ? '${_countdown}s' : '获取验证码',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _loggingIn ? null : _onLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loggingIn
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '登录',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '未注册手机号验证后将自动创建账号',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 8),
              const Text(
                '开发环境验证码：123456',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _blue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
