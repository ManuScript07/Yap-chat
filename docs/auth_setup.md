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

   Маска `/**` обязательна: мобильный клиент добавляет к callback случайный
   `auth_attempt`, чтобы Supabase принимал только ответ от текущего окна
   авторизации и игнорировал закрытые либо устаревшие окна.

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

### Защита UserInfo от ресурсного спама

Перед обновлением функции примените миграцию
`202610120001_harden_yandex_userinfo.sql`:

```shell
npx supabase db push
npx supabase functions deploy yandex-userinfo --no-verify-jwt
```

UserInfo URL менять не нужно. Дополнительных секретов не требуется: функция
использует стандартные серверные `SUPABASE_URL` и `SUPABASE_SERVICE_ROLE_KEY`.
Клиенту эти значения не передаются. Не включайте проверку Supabase JWT для
этой функции: Supabase Auth присылает токен Яндекса до создания сессии.

Принимаются только GET без тела/query-параметров и заголовок Authorization
с типом Bearer либо OAuth. Токен ограничен 4096 символами; проверяется общая
синтаксическая форма, а не конкретный префикс или длина токенов Яндекса.
Запрос к квоте ограничен 1,5 секунды, к Яндексу вместе с чтением ответа —
5 секундами. Ответ Яндекса ограничен 16 KiB. Автоматических повторов нет.

Общая для всех экземпляров квота допускает по умолчанию **10 обращений на
один токен за минуту** и **600 обращений суммарно за минуту**. В БД попадает
только HMAC токена с доменным префиксом, не токен или данные пользователя.
Отказ Яндекса также расходует квоту. Публичный RPC доступен исключительно
service_role; таблицы и повышенная реализация находятся в private.

Счётчики занимают не более 6000 строк токенов; устаревшие строки удаляются
ограниченными порциями при новых ключах и раз в час через pg_cron.
Задание `cleanup-yandex-userinfo-quota` не обращается к внешним сервисам.
Если pg_cron отсутствует, ограничение размера и очистка при обращениях
сохраняются, но отдельная очистка в простое не запускается.

Предел 600 — стартовый аварийный бюджет, а не ограничение на число пользователей
или активных сессий. Подберите его с запасом по реальному пику авторизаций.
При необходимости администратор может изменить конфигурацию без нового билда:

```sql
-- Пример изменения; значения подбираются по трафику, а не вслепую.
update private.yandex_userinfo_quota
set global_limit = 600, token_limit = 10, max_token_keys = 6000
where singleton;
```

Повторные отказы запоминаются в экземпляре функции до конца указанной паузы:
отказ для токена не мешает другим токенам, отказ общей квоты временно отсеивает
все обращения этого экземпляра до БД. Кэш ограничен 1024 HMAC-ключами и никогда
не разрешает вход вместо серверной проверки. Недоступность БД включает паузу
на одну секунду; одновременно выполняются не более 64 проверок квоты на
экземпляр. Это снижает повторную работу, но не заменяет защиту платформы от
DDoS и не ограничивает суммарный HTTP-трафик между всеми экземплярами.
Изменения администратором лимитов могут учитываться кэшем отказов с задержкой
до минуты. Данные успешных входов и ответы Яндекса не кэшируются.

Превышение квоты возвращает 429 и Retry-After; недоступность квоты — 503,
без обхода ограничений. Общий бюджет может быть исчерпан злоумышленником:
это ограничение стоимости внешних запросов, а не полная DDoS-защита.
Каждая проверка, не отсечённая кэшем отказов, добавляет один серверный RPC, но обычное
восстановление сессии, refresh, чаты и Realtime функцию не вызывают.
Настройки Authentication → Rate Limits этой миграцией не изменяются.

Проверки (без настоящих токенов/запросов к Яндексу):

```shell
node --test supabase/tests/yandex_userinfo.test.mjs
node supabase/tests/yandex_userinfo_local.mjs
npx --yes deno check supabase/functions/yandex-userinfo/index.ts
```

Локальный интеграционный тест требует Docker и уже применённую миграцию
в локальном проекте. Он проверяет реальный PostgREST, создаёт отдельную
временную БД для конкурентных тестов и удаляет только её/свой тестовый ключ.
На продакшене нагрузочные тесты не запускайте. После деплоя проверьте новый
вход и регистрацию через Яндекс; при откате возвращайте предыдущую функцию,
не удаляя пользователей и не меняя OAuth/PKCE-конфигурацию.

Flutter-клиент передаёт `force_confirm=yes` в OAuth-запросе. Благодаря этому
Yandex показывает подтверждение и выбор аккаунта даже при наличии активной
браузерной сессии, а не молча авторизует предыдущий аккаунт.

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
