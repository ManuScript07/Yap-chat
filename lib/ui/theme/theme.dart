export 'app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// 1. Палитра цветов из Figma
abstract class AppColors {
  static const Color background = Color(0xFF13140D); // Основной цвет фона
  static const Color textPrimary = Color(0xFFF9F9F9); // Основной текст / Иконки
  static const Color textSecondary = Color(0xFFAAAAAA); // Второстепенный текст
  static const Color brandPrimary = Color(0xFF03A6E1); // Основной бренд цвет
  static const Color onBrandPrimary = Color(0xFF000000);

  // Подложки и инпуты
  static const Color surfaceOverlay = Color(0xFFFFFFFF);

  static const Color borderInactive = Color(0xFF6E7586); // Неактивные границы
  static const Color incomingBubble = Color(
    0xFFBEEEFF,
  ); // Пузырь входящего сообщения
  static const Color incomingText = Color(
    0xFF001E2F,
  ); // Текст входящего сообщения
  static const Color incomingTime = Color(
    0xFF5A5F6A,
  ); // Время входящего сообщения
}

/// 2. ThemeData с конфигурацией под чат
final ThemeData theme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.onBrandPrimary,

  // Цветовая схема
  colorScheme: ColorScheme.dark(
    primary: AppColors.brandPrimary,
    onPrimary: AppColors.onBrandPrimary,
    surface: AppColors.surfaceOverlay,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.borderInactive,
  ),

  // Настройка текстовых стилей по умолчанию
  textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme),

  // Настройка полей ввода (TextField)
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceOverlay,
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.borderInactive),
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
      borderRadius: BorderRadius.circular(12),
    ),
  ),

  // Настройка AppBar
  appBarTheme: const AppBarTheme(
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.light, // Темные иконки сверху
      systemNavigationBarIconBrightness:
          Brightness.light, // Темные кнопки снизу
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  ),
);
