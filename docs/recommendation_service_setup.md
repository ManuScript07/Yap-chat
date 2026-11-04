# Внутренний сервис рекомендаций

Микросервис находится в отдельном репозитории `D:/yap-algorithm`. Каноническая схема и RPC принадлежат этому приложению: `20261104195702_feed_recommendation_pipeline.sql` и `20261104213317_personalized_feed.sql` в `supabase/migrations`.

Клиент использует Supabase Auth и RPC. `create_feed_post`, `edit_feed_post`, `delete_feed_post`, `get_feed_post` работают с текстовыми постами. Триггер ставит индексационное задание в `recsys.index_jobs`, а `cmd/worker` сохраняет E5-вектор в той же базе. Новая очередь `recsys.refresh_jobs` объединяет пересчёты профиля и персональной выдачи. У Go нет клиентского HTTP API.

Клиентский контракт: `yap-algorithm/api/supabase.openapi.yaml`. Основные RPC — `get_for_you_feed`, `apply_feed_action`, `record_feed_events`, `set_recommendation_author_hidden`, `reset_recommendation_interests`, `get_recommendation_hidden_authors`. Пагинация использует UUID сессии и позицию; актуальные баны, блокировки, дружба, версии и скрытия проверяются при каждом чтении. Повторы сохраняют UUID и тело запроса, действия по посту дополнительно требуют `action_version`.

Новые публикации: 12 за скользящий час на пользователя. Счётчик не сбрасывается удалением поста. Чтение и обратная связь используют отдельные атомарные квоты, существующие квоты чатов не меняются.

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

Проверки прав: `feed_recommendation_boundary.sql` и `personalized_feed_boundary.sql` в `supabase/tests`. Сквозные тесты сервиса запускаются из его репозитория:

```powershell
./scripts/test-supabase-local.ps1 -AppRoot D:/StudioProjects/Yap_chat -WithModel
```

Работают персональные снимки «Для вас», показы, чтение, лайки/отмены, отрицательная семантика, скрытие автора и сброс. Поверхности `direct` и `for_you` используют общий профиль. Отдельные выдачи друзей/географии, репосты, комментарии, жалобы и фото добавляются следующими этапами. Flutter-репозитории, кэш и сетевой слой пока не менялись. Облачное развёртывание ещё не проверялось.
