# Очистка фотографий после удаления аккаунта

Миграции `202609100005_cleanup_finalized_profile_media.sql` и
`202609100007_use_dedicated_profile_media_cleanup_token.sql` создают очередь
физического удаления файлов из bucket `avatars` и почасовой cron-job. Он
запускает Edge Function `cleanup-finalized-profile-media` через `pg_net`.

Перед включением задачи один раз добавьте в **Supabase Dashboard → SQL Editor**
два значения в Vault. Значения не должны попадать в git или миграции.

```sql
select vault.create_secret(
  'https://<project-ref>.supabase.co',
  'account_deletion_cleanup_project_url'
);

select vault.create_secret(
  '<RANDOM_SCHEDULER_TOKEN>',
  'account_deletion_cleanup_scheduler_token'
);
```

`<RANDOM_SCHEDULER_TOKEN>` — отдельный случайный токен, а не API-ключ
Supabase. Задайте ровно это же значение как Edge Function secret и задеплойте
функцию:

```bash
supabase secrets set \
  ACCOUNT_DELETION_CLEANUP_SCHEDULER_TOKEN=<RANDOM_SCHEDULER_TOKEN>

supabase functions deploy cleanup-finalized-profile-media --no-verify-jwt
```

Сгенерировать токен в PowerShell можно так — не сохраняйте результат в Git:

```powershell
[Convert]::ToHexString(
  [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
).ToLowerInvariant()
```

Проверить выполнение можно в **Integrations → Cron** по задаче
`cleanup-finalized-profile-media`; она запускается в `:23` каждого часа, после
финализатора аккаунтов в `:17`. Пока Vault-секреты не добавлены, задача не
отправляет HTTP-запрос и не выдаёт ошибку.

Функция принимает только POST с этим отдельным токеном, берёт из закрытой
очереди максимум 250 уже финализированных файлов и удаляет их исключительно
через Storage API.
Ошибки сохраняются в очереди с экспоненциальной паузой и не требуют участия
пользовательского приложения.
