import 'package:flutter/material.dart';

/// 앱 전체에서 재사용하는 색상 토큰.
/// BoxHero류 재고관리 앱을 참고해 화려한 그라데이션/그림자 대신
/// 흰 배경 + 얇은 경계선 위주의 차분하고 정돈된 톤을 지향합니다.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF4C63E8);
  static const Color primaryDark = Color(0xFF3B4FC4);

  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Colors.white;

  static const Color textPrimary = Color(0xFF1E2230);
  static const Color textSecondary = Color(0xFF8A8F9E);
  static const Color border = Color(0xFFE7E8EE);

  // 보관중 / 성공 계열
  static const Color success = Color(0xFF1C9A5B);
  static const Color successBg = Color(0xFFE8F6EE);

  // 출고 계열
  static const Color warning = Color(0xFFDB8A1F);
  static const Color warningBg = Color(0xFFFCF1E0);

  // 입고 계열
  static const Color info = Color(0xFF3271E6);
  static const Color infoBg = Color(0xFFEAF1FD);

  // 위험/삭제 계열
  static const Color danger = Color(0xFFDB3B5C);
  static const Color dangerBg = Color(0xFFFCEAEF);
}

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(primary: AppColors.primary, surface: AppColors.surface),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.1,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primary.withValues(alpha: 0.10),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
      height: 62,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? AppColors.primary : AppColors.textSecondary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? AppColors.primary : AppColors.textSecondary,
        );
      }),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
      contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border, width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: AppColors.border, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
      ),
    ),

    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),

    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
      contentTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),

    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
  );
}

/// 출고/보관중/입고 등 상태별 배지에 쓰는 (전경색, 배경색) 묶음.
class StatusPalette {
  final Color fg;
  final Color bg;
  const StatusPalette(this.fg, this.bg);

  static const stored = StatusPalette(AppColors.success, AppColors.successBg); // 보관중
  static const rented = StatusPalette(AppColors.warning, AppColors.warningBg); // 대여중 / 출고
  static const checkin = StatusPalette(AppColors.info, AppColors.infoBg); // 입고
  static const danger = StatusPalette(AppColors.danger, AppColors.dangerBg);
  static const primary = StatusPalette(AppColors.primary, Color(0xFFEBEEFC));
}
