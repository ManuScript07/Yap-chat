# Android push notifications

The app uses FCM **data-only** payloads with a Supabase transactional outbox.
The Flutter foreground/background handlers display local Android notifications
and use the same payload for navigation. Muted chats do not enqueue message
pushes; delivery rechecks mute, visibility, both directions of blocking, and
account availability, including for previously queued events.

All Android notifications use the monochrome `@drawable/ic_notification`
resource as their status-bar small icon. The local notification service uses it;
the FCM manifest default is also retained.

## 1. Create the Firebase Android app

1. Create a project in Firebase Console.
2. Add an Android application with package name `com.yapchat.app`.
3. Add the SHA-256 fingerprints for the debug and release signing keys.
4. Run the standard FlutterFire setup from the project root:

   ```powershell
   dart pub global activate flutterfire_cli
   flutterfire configure --platforms=android
   ```

5. Confirm that `android/app/google-services.json` exists and that FlutterFire
   added the Google Services Gradle plugin.
6. Enable Firebase Cloud Messaging API (HTTP v1) in the Google Cloud project.
7. Use `APP_ENV=prod` in the cloud build; push is intentionally disabled for
   `dev` and `local` repository containers.

`google-services.json` and generated `firebase_options.dart` identify the
Firebase project but do not contain server credentials. They may be committed.

The package name changed from `com.example.yap_chat` to `com.yapchat.app`.
Update the Android application entry in Yandex OAuth and reinstall the app.

## 2. Create server credentials

1. Open Firebase Console → Project settings → Service accounts.
2. Generate a new private key and keep the downloaded JSON outside Git.
3. Convert the JSON to one line and create `supabase/.env.push.local`:

   ```powershell
   $json = Get-Content C:\secure\firebase-service-account.json -Raw |
     ConvertFrom-Json | ConvertTo-Json -Compress
   "FIREBASE_SERVICE_ACCOUNT=$json" | Set-Content supabase/.env.push.local
   "PUSH_WEBHOOK_SECRET=<a-long-random-secret>" |
     Add-Content supabase/.env.push.local
   ```

4. Upload the secrets to the linked Supabase project:

   ```powershell
   npx supabase secrets set --env-file supabase/.env.push.local
   ```

Never commit the service-account JSON or `supabase/.env.push.local`.

## 3. Deploy Supabase changes

```powershell
npx supabase db push
npx supabase functions deploy push-message --no-verify-jwt
```

Migration `202610110003_harden_push_delivery.sql` retains the existing RPCs and
INSERT webhook. Clients can SELECT only their own devices and mutate them only
through guarded RPCs. Registration is serialized per account: at most 10 rows,
60 registrations/minute; oldest device eviction matches the existing behavior.
Pre-existing excess rows are disabled during migration rather than bulk deleted.
The outbox and worker RPCs remain inaccessible to client roles.

## 4. Create the Database Webhook

In Supabase Dashboard open Database → Webhooks and create a webhook with:

- table: `public.push_notification_outbox`
- event: `INSERT`
- method: `POST`
- URL: `https://<project-ref>.supabase.co/functions/v1/push-message`
- header: `x-webhook-secret: <the same PUSH_WEBHOOK_SECRET>`

The function has JWT verification disabled only because it authenticates this
server-to-server request with the separate webhook secret.

## 5. Enable durable recovery (required for retries)

Enable `pg_cron`, `pg_net` and Vault (the project's existing cleanup uses them).
In the SQL editor, store these two Vault values **once**. The webhook secret
must exactly match `PUSH_WEBHOOK_SECRET`; never put the real value in Git:

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'push_delivery_project_url');
select vault.create_secret('<same-long-random-webhook-secret>', 'push_delivery_webhook_secret');
```

If these names already exist, use `vault.update_secret(id, new_secret)` instead
of creating duplicates. The migration installs:

- `retry-push-notifications`: each minute, calls the same worker **only when
  due jobs exist**, up to 20 jobs with 4 concurrent jobs / 40 FCM requests.
- `cleanup-push-notification-outbox`: hourly, removes at most 5000 terminal
  `sent`/`failed` rows older than 7 days. Messages/media are not removed.

For an existing production deployment, temporarily disable the INSERT webhook
and let current invocations finish before applying the migration. Then deploy
the worker, configure Vault and re-enable the webhook. Recovery catches up the
pending jobs. Do not run the old worker against the new migration concurrently.

```sql
select jobname, schedule, active from cron.job
where jobname in ('retry-push-notifications', 'cleanup-push-notification-outbox');
```

No scheduled request goes to Firebase while the queue is empty. This adds no
client timers, RPCs or Realtime channels. Normal eligible delivery now needs
two database RPCs (claim/finish), with delivery guards inside the claim.

### Delivery contract

- A push expires 24 hours after enqueueing; FCM receives only its **remaining**
  TTL. Expiry affects the notification, never message history.
- A token can receive only jobs created after its registration for that account.
  Foreground/token refresh of the same token preserves this epoch; a new token
  or account transfer starts a new epoch. Installing again does not replay the
  old outbox to the new installation; normal chat sync retrieves the messages.
- DB-owned attempts (max 8), 2-minute fenced lease, and persisted exponential
  retry (60s → 120s … 30min, plus up to 15s jitter). `Retry-After` can extend this
  delay; the database caps it at 24h. Network errors and 429/5xx/401 retry, other
  permanent errors terminate. Confirmed invalid tokens are disabled.
- Accepted devices are checkpointed, so a partial failure retries only remaining
  devices. A crash **between FCM acceptance and DB checkpoint** can still cause
  one duplicate: delivery is at-least-once, not exactly-once. `sent` means FCM
  acceptance or a recorded skip, not guaranteed Android display.
- No collapse-key/sound/grouping behavior was changed. A flood to an existing
  offline installation is a separate FCM/client aggregation concern, not the
  reinstall replay case; there is no claim that all notification spam is solved.

Provider guidance: [FCM error/retry rules](https://firebase.google.com/docs/cloud-messaging/error-codes)
and [message TTL](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan).

## 6. Verify

1. Install a fresh build on two physical Android devices with Google Play
   Services.
2. Complete registration; Android should request notification permission only
   after the profile becomes complete.
3. Verify a row for each installation in `public.push_devices` using Supabase
   Dashboard.
4. Send text, photo, audio, and location messages while the recipient app is
   backgrounded.
5. Verify `public.push_notification_outbox.status = 'sent'`,
   `delivery_result = 'delivered_to_fcm'`, and
   `delivered_device_count > 0`. A muted conversation intentionally creates no
   outbox row.
6. Tap a notification and confirm that the corresponding chat opens.

Real FCM delivery is intentionally disabled for `APP_ENV=local`; local Supabase
continues to use the no-op notification repository.

Local checks (Node 24+, Docker Supabase running, migration applied):

```powershell
node --test supabase/tests/push_worker.test.mjs
node supabase/tests/push_delivery_local.mjs
node supabase/tests/push_delivery_rest.mjs
node supabase/tests/push_delivery_cron.mjs
Get-Content supabase/tests/push_delivery.sql -Raw | docker exec -i supabase_db_Yap_chat psql -U postgres -d postgres -X -v ON_ERROR_STOP=1
Get-Content supabase/tests/push_backlog.sql -Raw | docker exec -i supabase_db_Yap_chat psql -U postgres -d postgres -X -v ON_ERROR_STOP=1
npx deno check --node-modules-dir=auto --no-lock supabase/functions/push-message/index.ts
npx deno lint --rules-exclude=no-import-prefix supabase/functions/push-message/index.ts supabase/functions/push-message/worker.ts
```

SQL fixtures roll back; the concurrent integration test removes only its random
fixture UUIDs. FCM is injected/mocked: these tests do not use service-account
credentials or contact Google. The cron test requires the two local push Vault
names to be absent, temporarily supplies test values and waits up to 65 seconds
for a real cron tick; it removes only its own values afterward. It must run
alone, not alongside other push fixture suites. Finish with a real two-device smoke test after
deployment, including mute, logout/login and reinstall.
