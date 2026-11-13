# Публичный контент приложения

Публичные ссылки хранятся в `legal-documents/app-content.json` в Supabase
Storage. Bucket открыт только на чтение: загрузка и замена выполняются через
Dashboard либо service role. Мобильное приложение не вызывает для этого
PostgreSQL/RPC и держит корректный manifest локально шесть часов.

1. Загрузите PDF в `legal-documents` с новыми, неизменяемыми именами, например
   `terms-ru-v4.pdf`. Не перезаписывайте старый файл: сначала загрузите новый,
   затем переключите manifest.
2. Загрузите `app-content.json` с типом `application/json`:

```json
{
  "supportEmail": "support@example.com",
  "termsUrlRu": "https://<project-ref>.supabase.co/storage/v1/object/public/legal-documents/terms-ru-v4.pdf",
  "termsUrlEn": "https://<project-ref>.supabase.co/storage/v1/object/public/legal-documents/terms-en-v4.pdf",
  "privacyPolicyUrlRu": "https://<project-ref>.supabase.co/storage/v1/object/public/legal-documents/privacy-ru-v4.pdf",
  "privacyPolicyUrlEn": "https://<project-ref>.supabase.co/storage/v1/object/public/legal-documents/privacy-en-v4.pdf",
  "telegramUrl": "https://t.me/<channel>",
  "githubUrl": "https://github.com/<organization>/<repository>",
  "updatedAt": "2026-09-08T00:00:00Z"
}
```

`support_email` в `private.app_public_content` остаётся резервом только для
`get_my_account_access`: так впервые забаненный пользователь увидит контакты
ещё до загрузки manifest. Поддерживайте его равным `supportEmail` в JSON.
