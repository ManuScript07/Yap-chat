import 'dart:ui';

import 'package:phone_numbers_parser/phone_numbers_parser.dart';

class PhoneNumberNormalizer {
  PhoneNumberNormalizer({Locale Function()? localeProvider})
    : _localeProvider =
          localeProvider ?? (() => PlatformDispatcher.instance.locale);

  final Locale Function() _localeProvider;

  String? get localCountryCallingCode {
    final country = _callerCountry();
    if (country == null) return null;
    return PhoneNumber(isoCode: country, nsn: '').countryCode;
  }

  int get localNationalMaxLength {
    final country = _callerCountry();
    final callingCodeLength = localCountryCallingCode?.length ?? 0;
    final e164Maximum = 15 - callingCodeLength;
    if (country == null || e164Maximum <= 0) return 15;

    for (var length = e164Maximum; length > 0; length--) {
      final digits = List.filled(length, '9').join();
      if (PhoneNumber(isoCode: country, nsn: digits).isValidLength()) {
        return length;
      }
    }
    return e164Maximum;
  }

  String formatLocalNationalNumber(String rawNationalNumber) {
    final digits = _digitsOnly(rawNationalNumber);
    final country = _callerCountry();
    if (country == null || digits.isEmpty) return digits;
    return PhoneNumberFormatter.formatNsn(digits, country);
  }

  String? normalizeLocalNationalNumber(String rawNationalNumber) {
    final callingCode = localCountryCallingCode;
    if (callingCode == null) return normalize(rawNationalNumber);

    final nationalDigits = _digitsOnly(rawNationalNumber);
    if (nationalDigits.isEmpty) return null;
    return normalize('+$callingCode$nationalDigits');
  }

  String? normalize(String rawPhone) {
    final trimmed = rawPhone.trim();
    final callerCountry = _callerCountry();
    if (trimmed.isEmpty ||
        (!trimmed.startsWith('+') && callerCountry == null)) {
      return null;
    }
    try {
      final parsed = PhoneNumber.parse(
        trimmed,
        callerCountry: trimmed.startsWith('+') ? null : callerCountry,
      );
      return parsed.isValid() ? parsed.international : null;
    } catch (_) {
      return null;
    }
  }

  IsoCode? _callerCountry() {
    final countryCode = _localeProvider().countryCode?.toUpperCase();
    if (countryCode == null || countryCode.isEmpty) return null;
    try {
      return IsoCode.fromJson(countryCode);
    } catch (_) {
      return null;
    }
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');
}
