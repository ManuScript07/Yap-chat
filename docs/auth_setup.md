# Настройка Supabase и Yandex ID

## 1. Supabase Cloud

1. Создайте проект в Supabase Dashboard.
2. Установите Supabase CLI и свяжите репозиторий с проектом:

   ```shell
   supabase login
   supabase link --project-ref <project-ref>
   supabase db push
   ```

3. Разверните адаптер Yandex UserInfo:

   ```shell
   supabase functions deploy yandex-userinfo --no-verify-jwt
   ```

4. В `Authentication > URL Configuration` укажите:

   - Site URL для Web-разработки: `http://localhost:3000`;
   - дополнительный Redirect URL: `yapchat://login-callback/**`;
   - Web-приложение запускайте с фиксированным портом:
     `flutter run -d chrome --web-port 3000`.

5. Скопируйте Project URL и Publishable key в локальный `.env`:

   ```dotenv
   APP_ENV=prod
   SUPABASE_URL=https://<project-ref>.supabase.co
   SUPABASE_PUBLISHABLE_KEY=<publishable-key>
   AUTH_REDIRECT_URL=yapchat://login-callback/
   ```

Publishable key является клиентским ключом. `service_role`, secret key и Yandex
Client Secret нельзя добавлять в Flutter или коммитить в Git.

## 2. Приложение Yandex OAuth

1. Откройте страницу создания приложения Yandex OAuth.
2. Выберите тип «Для авторизации пользователей».
3. Укажите название, иконку и контактную почту.
4. Для текущей серверной OAuth-схемы добавьте платформу «Веб-сервисы».
5. В Redirect URI укажите callback Supabase:

   ```text
   https://<project-ref>.supabase.co/auth/v1/callback
   ```

6. Запросите только необходимые разрешения Yandex ID:

   - `login:info` — имя пользователя;
   - `login:email` — email;
   - `login:avatar` — портрет;
   - `login:birthday` — дата рождения;
   - `login:default_phone` — подтверждённый номер телефона.

7. Сохраните Client ID и Client Secret. Secret понадобится только в настройках
   Supabase custom provider.

## 3. Custom OAuth provider в Supabase

В `Authentication > Providers > New Provider > Manual configuration` создайте:

| Поле | Значение |
| --- | --- |
| Identifier | `custom:yandex` |
| Authorization URL | `https://oauth.yandex.com/authorize` |
| Token URL | `https://oauth.yandex.com/token` |
| UserInfo URL | `https://<project-ref>.supabase.co/functions/v1/yandex-userinfo` |
| Client ID | Client ID приложения Yandex OAuth |
| Client Secret | Client Secret приложения Yandex OAuth |
| Scopes | `login:info login:email login:avatar login:birthday login:default_phone` |
| PKCE | включён |
| Email optional | выключен |

Функция `yandex-userinfo` преобразует Yandex-заголовок `OAuth` и поля
`id/default_email/real_name/default_avatar_id/default_phone` в UserInfo-ответ,
который ожидает Supabase Custom OAuth2.

## 4. Юридические документы

1. Заполните заготовки в `docs/legal/` и проверьте их с юристом.
2. Опубликуйте документы по HTTPS.
3. Добавьте адреса в `.env`:

   ```dotenv
   PRIVACY_POLICY_URL=https://your-domain.example/privacy
   TERMS_OF_SERVICE_URL=https://your-domain.example/terms
   ```

4. При изменении документов обновите `terms_version` отдельной миграцией и
   реализуйте повторное согласие пользователей.

Дата рождения и сведения о согласиях доступны только владельцу профиля по RLS.
Для будущего поиска друзей следует создать отдельное безопасное представление
только с `id`, `username`, `display_name` и `avatar_url`.

## 5. Перенос на VPS

Храните схему только через `supabase/migrations`. При переносе отдельно
потребуется восстановить базу, перенести Storage, развернуть Edge Functions,
заново настроить Yandex provider и изменить его Redirect URI. Пользовательские
аккаунты сохраняются, но после смены JWT-ключей пользователям понадобится войти
повторно.
