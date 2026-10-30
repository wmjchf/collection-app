import 'package:flutter/material.dart';
import 'package:super_collection/features/settings/settings_modal.dart';
import 'package:super_collection/features/settings/settings_panel.dart';

/// 设置页（对齐 Figma `24. 设置`）；内容与账户抽屉共用 [SettingsPanel]。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leadingWidth: SettingsBackButton.leadingWidth,
        leading: const SettingsBackButton(),
        title: const Text(
          '设置',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: const SettingsPanel(),
    );
  }
}
