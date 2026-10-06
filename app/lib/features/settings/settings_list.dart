import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.of(context).muted,
      ),
    );
  }
}

class SettingsCardGroup extends StatelessWidget {
  const SettingsCardGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class SettingsInfoRow extends StatelessWidget {
  const SettingsInfoRow({
    super.key,
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
    final colors = AppColors.of(context);
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
                  color: colors.ink,
                ),
              ),
            ),
            if (trailing != null) trailing!,
            if (showChevron)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: colors.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
