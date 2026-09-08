import 'package:equatable/equatable.dart';

enum LegalDocument { terms, privacyPolicy }

/// Non-sensitive, server-managed information shown by the app.
class AppPublicContent extends Equatable {
  const AppPublicContent({
    this.supportEmail,
    this.termsUrlRu,
    this.termsUrlEn,
    this.privacyPolicyUrlRu,
    this.privacyPolicyUrlEn,
    this.telegramUrl,
    this.githubUrl,
    this.updatedAt,
  });

  final String? supportEmail;
  final String? termsUrlRu;
  final String? termsUrlEn;
  final String? privacyPolicyUrlRu;
  final String? privacyPolicyUrlEn;
  final String? telegramUrl;
  final String? githubUrl;
  final DateTime? updatedAt;

  String? legalUrl(LegalDocument document, String languageCode) {
    final isEnglish = languageCode == 'en';
    return switch (document) {
      LegalDocument.terms =>
        isEnglish ? termsUrlEn ?? termsUrlRu : termsUrlRu ?? termsUrlEn,
      LegalDocument.privacyPolicy =>
        isEnglish
            ? privacyPolicyUrlEn ?? privacyPolicyUrlRu
            : privacyPolicyUrlRu ?? privacyPolicyUrlEn,
    };
  }

  Map<String, Object?> toJson() => {
    'supportEmail': supportEmail,
    'termsUrlRu': termsUrlRu,
    'termsUrlEn': termsUrlEn,
    'privacyPolicyUrlRu': privacyPolicyUrlRu,
    'privacyPolicyUrlEn': privacyPolicyUrlEn,
    'telegramUrl': telegramUrl,
    'githubUrl': githubUrl,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  factory AppPublicContent.fromJson(Map<String, dynamic> json) =>
      AppPublicContent(
        supportEmail: _optionalString(json['supportEmail']),
        termsUrlRu: _optionalString(json['termsUrlRu']),
        termsUrlEn: _optionalString(json['termsUrlEn']),
        privacyPolicyUrlRu: _optionalString(json['privacyPolicyUrlRu']),
        privacyPolicyUrlEn: _optionalString(json['privacyPolicyUrlEn']),
        telegramUrl: _optionalString(json['telegramUrl']),
        githubUrl: _optionalString(json['githubUrl']),
        updatedAt: DateTime.tryParse(
          _optionalString(json['updatedAt']) ?? '',
        )?.toUtc(),
      );

  static String? _optionalString(Object? value) {
    final result = value is String ? value.trim() : '';
    return result.isEmpty ? null : result;
  }

  @override
  List<Object?> get props => [
    supportEmail,
    termsUrlRu,
    termsUrlEn,
    privacyPolicyUrlRu,
    privacyPolicyUrlEn,
    telegramUrl,
    githubUrl,
    updatedAt,
  ];
}
