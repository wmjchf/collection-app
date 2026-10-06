import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/core/ui/app_icon_sizes.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppColors.light);

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.brand,
      onPrimary: Colors.white,
      secondary: colors.brand,
      onSecondary: Colors.white,
      error: colors.danger,
      onError: Colors.white,
      surface: colors.card,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      outline: colors.hairline,
    );
    final overlay = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: colors.card,
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: colors.card,
            systemNavigationBarIconBrightness: Brightness.dark,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.pageBg,
      cardColor: colors.card,
      dividerColor: colors.hairline,
      iconTheme: IconThemeData(size: AppIconSizes.theme, color: colors.ink),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          iconSize: AppIconSizes.theme,
          foregroundColor: colors.ink,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colors.card,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlay,
      ),
      dialogTheme: DialogThemeData(backgroundColor: colors.card),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.card,
        textStyle: TextStyle(color: colors.ink, fontSize: 15),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: colors.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
      ),
      extensions: [colors],
    );
  }
}
