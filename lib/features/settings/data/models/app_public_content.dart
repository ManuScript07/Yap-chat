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
    this.updatedAt,
  });

  final String? supportEmail;
  final String? termsUrlRu;
  final String? termsUrlEn;
  final String? privacyPolicyUrlRu;
  final String? privacyPolicyUrlEn;
  final String? telegramUrl;
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
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  factory AppPublicContent.fromJson(Map<String, dynamic> json) =>
      AppPublicContent(
        supportEmail: json['supportEmail'] as String?,
        termsUrlRu: json['termsUrlRu'] as String?,
        termsUrlEn: json['termsUrlEn'] as String?,
        privacyPolicyUrlRu: json['privacyPolicyUrlRu'] as String?,
        privacyPolicyUrlEn: json['privacyPolicyUrlEn'] as String?,
        telegramUrl: json['telegramUrl'] as String?,
        updatedAt: DateTime.tryParse(
          json['updatedAt'] as String? ?? '',
        )?.toUtc(),
      );

  @override
  List<Object?> get props => [
    supportEmail,
    termsUrlRu,
    termsUrlEn,
    privacyPolicyUrlRu,
    privacyPolicyUrlEn,
    telegramUrl,
    updatedAt,
  ];
}
