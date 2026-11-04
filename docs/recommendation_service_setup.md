# Внутренний сервис рекомендаций: первый этап

Микросервис находится в отдельном репозитории `D:/yap-algorithm`. Каноническая схема данных и RPC принадлежат этому приложению: `supabase/migrations/20261104195702_feed_recommendation_pipeline.sql`.

Клиент использует Supabase Auth и RPC. На этом этапе доступны `create_feed_post`, `edit_feed_post`, `delete_feed_post`, `get_feed_post` для текстовых постов. Транзакционный триггер ставит задание в `recsys.index_jobs`, а отдельный `cmd/worker` вычисляет E5-вектор и сохраняет его в `recsys.post_embeddings` той же базы. У Go нет клиентского HTTP API.

Применять нужно миграцию из этого репозитория через обычный процесс миграций проекта. Миграции/fixtures старого алгоритмического прототипа из `yap-algorithm/supabase` в эту базу не копируются. Worker не меняет схему при запуске.

На текущем ПК миграция уже применена к локальной Supabase. Логин worker настроен отдельно от пользователя postgres и ключей клиента.

```powershell
cd D:/yap-algorithm
./scripts/supabase-local.ps1 -Action setup -AppRoot D:/StudioProjects/Yap_chat
./scripts/local.ps1 -Action model
# После ready, в другом терминале:
./scripts/supabase-local.ps1 -Action worker
```

Сервисная роль `yap_recommendation_worker` имеет доступ только к внутренним функциям очереди. Клиентские функции продолжают использовать существующие проверки активного аккаунта, банов, удаления, блокировки и текущей дружбы. Новые лимиты закрыты в `private.feed_operation_limits` и не меняют квоты чатов. `feed` и `recsys` не надо добавлять к exposed schemas Data API.

Проверка прав: `supabase/tests/feed_recommendation_boundary.sql`. Сквозные тесты сервиса запускаются из его репозитория:

```powershell
./scripts/test-supabase-local.ps1 -AppRoot D:/StudioProjects/Yap_chat -WithModel
```

Подробные ограничения и архитектура описаны в `yap-algorithm/docs/supabase-pipeline.ru.md`. Персональные снимки «Для вас», взаимодействия, жалобы, комментарии, география и фото добавляются следующими этапами. Flutter-репозитории, кэш и сетевой слой пока не менялись.
