import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract class AppTextStyles {
  // Figma Yap: Auth page for GPT. Colors are supplied by each existing view.
  static const authWelcome = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 20 / 32,
    letterSpacing: .32,
    fontFeatures: [
      FontFeature('dlig'),
      FontFeature.liningFigures(),
      FontFeature.proportionalFigures(),
    ],
  );
  static const authSignInWith = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    height: 20 / 22,
    letterSpacing: .1,
  );
  static const onboardingTitle = TextStyle(
    fontSize: 42,
    fontWeight: FontWeight.w800,
    height: 52 / 42,
    letterSpacing: .42,
    fontFeatures: [
      FontFeature('dlig'),
      FontFeature.liningFigures(),
      FontFeature.proportionalFigures(),
    ],
  );
  static const onboardingDate = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    // Figma allows its 32px glyphs to paint beyond an 18px line box. Flutter
    // clips input/hint paragraphs; retain full glyph metrics in the 61px field.
    height: 1.15,
    letterSpacing: .5,
  );

  /// Shared body typography for chat messages and quoted-message previews.
  static const TextStyle messageBody = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 0.5,
  );

  /// Заголовок "Чатикс" на Roboto Flex со всеми осями Figma
  static const TextStyle titleLargeFlex = TextStyle(
    fontFamily: 'RobotoFlex',
    fontSize: 52,
    letterSpacing: 0.5,
    height: 1.0,
    fontVariations: [
      FontVariation('wght', 766),
      FontVariation('GRAD', 150),
      FontVariation('XOPQ', 106),
      FontVariation('YTLC', 518),
      FontVariation('slnt', -10),
    ],
  );

  /// Имя собеседника (Roboto)
  static TextStyle chatName = GoogleFonts.roboto(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.33,
  );

  /// Предпросмотр сообщения (Roboto)
  static TextStyle messagePreview = GoogleFonts.roboto(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.25,
  );

  /// Метаданные / Время (Roboto)
  static TextStyle metadata = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.14,
  );

  /// Текст в счетчике (Roboto)
  static TextStyle badgeText = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.14,
  );
}
