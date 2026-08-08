import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract class AppTextStyles {
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
    height: 1.33
  );

  /// Предпросмотр сообщения (Roboto)
  static TextStyle messagePreview = GoogleFonts.roboto(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.25
  );

  /// Метаданные / Время (Roboto)
  static TextStyle metadata = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.14
  );

  /// Текст в счетчике (Roboto)
  static TextStyle badgeText = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.14
  );
}

