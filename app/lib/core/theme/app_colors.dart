import 'package:flutter/material.dart';

/// 浅色对齐现有界面色；深色为同结构的暗色表面。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.pageBg,
    required this.card,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.brand,
    required this.brandSoft,
    required this.danger,
    required this.inputBg,
    required this.selectedFill,
    required this.placeholder,
    required this.iconMuted,
    required this.highlight,
  });

  final Color pageBg;
  final Color card;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color brand;
  final Color brandSoft;
  final Color danger;
  final Color inputBg;
  final Color selectedFill;
  final Color placeholder;
  final Color iconMuted;
  final Color highlight;

  static const light = AppColors(
    pageBg: Color(0xFFF7F7FA),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF1F242E),
    muted: Color(0xFF737A85),
    hairline: Color(0xFFE6E8EB),
    brand: Color(0xFF2F6FED),
    brandSoft: Color(0xFFE8F0FF),
    danger: Color(0xFFD14343),
    inputBg: Color(0xFFF5F7FA),
    selectedFill: Color(0xFFF0F5FF),
    placeholder: Color(0xFFB2B8BF),
    iconMuted: Color(0xFFC5CAD3),
    highlight: Color(0xFFFFF2C7),
  );

  static const dark = AppColors(
    pageBg: Color(0xFF12151A),
    card: Color(0xFF1C2128),
    ink: Color(0xFFE6E8ED),
    muted: Color(0xFF9AA1AB),
    hairline: Color(0xFF2E3540),
    brand: Color(0xFF5B8FF9),
    brandSoft: Color(0xFF24344F),
    danger: Color(0xFFE05B5B),
    inputBg: Color(0xFF252A32),
    selectedFill: Color(0xFF1A2A48),
    placeholder: Color(0xFF6B7280),
    iconMuted: Color(0xFF5C6370),
    highlight: Color(0xFF5C4E24),
  );

  static AppColors of(BuildContext context) {
    return Theme.of(context).extension<AppColors>() ?? AppColors.light;
  }

  @override
  AppColors copyWith({
    Color? pageBg,
    Color? card,
    Color? ink,
    Color? muted,
    Color? hairline,
    Color? brand,
    Color? brandSoft,
    Color? danger,
    Color? inputBg,
    Color? selectedFill,
    Color? placeholder,
    Color? iconMuted,
    Color? highlight,
  }) {
    return AppColors(
      pageBg: pageBg ?? this.pageBg,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      hairline: hairline ?? this.hairline,
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      danger: danger ?? this.danger,
      inputBg: inputBg ?? this.inputBg,
      selectedFill: selectedFill ?? this.selectedFill,
      placeholder: placeholder ?? this.placeholder,
      iconMuted: iconMuted ?? this.iconMuted,
      highlight: highlight ?? this.highlight,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      pageBg: Color.lerp(pageBg, other.pageBg, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      inputBg: Color.lerp(inputBg, other.inputBg, t)!,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
    );
  }
}
