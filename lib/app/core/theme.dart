import 'package:flutter/material.dart';

class AppColors extends ThemeExtension<AppColors> {
  final Color cardBackground;
  final Color borderColor;
  final Color accentPurple;
  final Color spentRed;
  final Color receivedGreen;
  final Color textGrey;
  final Color subTextGrey;

  const AppColors({
    required this.cardBackground,
    required this.borderColor,
    required this.accentPurple,
    required this.spentRed,
    required this.receivedGreen,
    required this.textGrey,
    required this.subTextGrey,
  });

  @override
  AppColors copyWith({
    Color? cardBackground,
    Color? borderColor,
    Color? accentPurple,
    Color? spentRed,
    Color? receivedGreen,
    Color? textGrey,
    Color? subTextGrey,
  }) {
    return AppColors(
      cardBackground: cardBackground ?? this.cardBackground,
      borderColor: borderColor ?? this.borderColor,
      accentPurple: accentPurple ?? this.accentPurple,
      spentRed: spentRed ?? this.spentRed,
      receivedGreen: receivedGreen ?? this.receivedGreen,
      textGrey: textGrey ?? this.textGrey,
      subTextGrey: subTextGrey ?? this.subTextGrey,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!,
      spentRed: Color.lerp(spentRed, other.spentRed, t)!,
      receivedGreen: Color.lerp(receivedGreen, other.receivedGreen, t)!,
      textGrey: Color.lerp(textGrey, other.textGrey, t)!,
      subTextGrey: Color.lerp(subTextGrey, other.subTextGrey, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  static const darkAppColors = AppColors(
    cardBackground: Color(0xFF111420),
    borderColor: Color(0xFF222938),
    accentPurple: Color(0xFF9E86FF),
    spentRed: Color(0xFFFF5A5A),
    receivedGreen: Color(0xFF2BD181),
    textGrey: Color(0xFF7A8499),
    subTextGrey: Color(0xFF8E9AA8),
  );

  static const lightAppColors = AppColors(
    cardBackground: Colors.white,
    borderColor: Color(0xFFE2E8F0),
    accentPurple: Color(0xFF6F44F9),
    spentRed: Color(0xFFDC2626),
    receivedGreen: Color(0xFF16A34A),
    textGrey: Color(0xFF64748B),
    subTextGrey: Color(0xFF334155),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8F9FD),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6F44F9),
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      useMaterial3: true,
      extensions: const [
        lightAppColors,
      ],
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFF1EDFF),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFF6F44F9));
          }
          return const IconThemeData(color: Color(0xFF64748B));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Color(0xFF6F44F9),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
          );
        }),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF1E293B)),
        titleTextStyle: TextStyle(
          color: Color(0xFF1E293B),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0C0F17),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
        surface: const Color(0xFF111420),
      ),
      useMaterial3: true,
      extensions: const [
        darkAppColors,
      ],
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0E111A),
        indicatorColor: const Color(0xFF221E3B),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFF9E86FF));
          }
          return const IconThemeData(color: Color(0xFF7A8499));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Color(0xFF9E86FF),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: Color(0xFF7A8499),
            fontSize: 12,
          );
        }),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
