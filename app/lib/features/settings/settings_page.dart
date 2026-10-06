import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/features/settings/settings_panel.dart';

/// 设置页（对齐 Figma `24. 设置`）；内容与账户抽屉共用 [SettingsPanel]。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _side = 80.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.pageBg,
      appBar: AppBar(
        centerTitle: true,
        leadingWidth: _side,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: colors.ink,
            padding: const EdgeInsets.only(left: 8),
          ),
          icon: const Icon(Icons.chevron_left, size: 30),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: Text(
          '设置',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
      ),
      body: const SettingsPanel(),
    );
  }
}
