-- Permanently remove chat data only after it has been unavailable to every
-- participant for a full retention period.  All work is server-side and
-- bounded, so regular chat reads/writes never have to scan historical data.

create table private.chat_media_cleanup_queue (
  id uuid primary key default extensions.gen_random_uuid(),
  bucket_id text not null check (bucket_id in ('chat-images', 'chat-audio')),
  storage_path text not null check (char_length(storage_path) between 1 and 1024),
  queued_at timestamptz not null default statement_timestamp(),
  last_attempt_at timestamptz,
  next_attempt_at timestamptz not null default statement_timestamp(),
  lease_expires_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  deleted_at timestamptz,
  unique (bucket_id, storage_path)
);

create index chat_media_cleanup_queue_due_idx
  on private.chat_media_cleanup_queue (next_attempt_at, queued_at, id)
  where deleted_at is null;

-- The first index finds recalls (including messages from finalised accounts)
-- without touching normal chat history.  The second lets the both-hidden
-- branch begin from the retention deadline rather than all hidden messages.
create index messages_global_cleanup_due_idx
  on public.messages (deleted_for_everyone_at, id)
  where deleted_for_everyone_at is not null;

create index message_hidden_for_users_cleanup_due_idx
  on public.message_hidden_for_users (hidden_at, message_id, user_id);

create index conversation_members_hidden_cleanup_due_idx
  on public.conversation_members (hidden_at, conversation_id, user_id)
  where hidden_at is not null;

-- A reply must remain readable when the quoted message reaches its retention
-- deadline.  PostgreSQL now clears the link atomically during deletion.
alter table public.messages
  drop constraint if exists messages_reply_to_message_id_fkey;

alter table public.messages
  add constraint messages_reply_to_message_id_fkey
  foreign key (reply_to_message_id)
  references public.messages(id)
  on delete set null;

alter table public.message_hidden_for_users
  alter column cleanup_after set default (now() + interval '90 days');

revoke all on table private.chat_media_cleanup_queue
  from public, anon, authenticated;

comment on table private.chat_media_cleanup_queue is
  'Durable service-only queue for deleting chat images and audio through the Storage API after permanent chat-data cleanup.';

-- Keep the persisted deadline aligned with the product's exact 90-day
-- retention window.  The finalizer also derives eligibility from the source
-- timestamp so pre-existing three-calendar-month rows are handled correctly.
create or replace function private.soft_delete_message_impl(
  target_message_id uuid,
  delete_for_everyone boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  target_message public.messages%rowtype;
  deletion_timestamp timestamptz := statement_timestamp();
begin
  select * into target_message
  from public.messages
  where id = target_message_id;

  if target_message.id is null or not public.is_conversation_member(
    target_message.conversation_id,
    current_user_id
  ) then
    raise exception 'message_access_denied';
  end if;

  if delete_for_everyone and target_message.sender_id = current_user_id then
    update public.messages
    set deleted_for_everyone_at = deletion_timestamp,
        cleanup_after = deletion_timestamp + interval '90 days'
    where id = target_message_id;

    update public.message_attachments
    set deleted_at = deletion_timestamp,
        cleanup_after = deletion_timestamp + interval '90 days'
    where message_id = target_message_id;
  else
    insert into public.message_hidden_for_users (message_id, user_id)
    values (target_message_id, current_user_id)
    on conflict (message_id, user_id) do nothing;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'conversation_id', target_message.conversation_id,
      'reason', 'deleted'
    ),
    'changed',
    'chat:' || target_message.conversation_id::text,
    true
  );

  perform realtime.send(
    jsonb_build_object(
      'conversation_id', target_message.conversation_id,
      'reason', 'deleted'
    ),
    'changed',
    'user:' || current_user_id::text || ':chats',
    true
  );
end;
$$;

create function private.claim_chat_media_cleanup_batch(
  requested_batch_size integer default 1000
)
returns table (
  id uuid,
  bucket_id text,
  storage_path text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_batch_size integer := least(greatest(coalesce(requested_batch_size, 1000), 1), 1000);
begin
  return query
  with due as (
    select queue.id
    from private.chat_media_cleanup_queue queue
    where queue.deleted_at is null
      and queue.next_attempt_at <= statement_timestamp()
      and (
        queue.lease_expires_at is null
        or queue.lease_expires_at <= statement_timestamp()
      )
    order by queue.next_attempt_at, queue.queued_at, queue.id
    limit normalized_batch_size
    for update skip locked
  ), claimed as (
    update private.chat_media_cleanup_queue queue
    set attempts = queue.attempts + 1,
        last_attempt_at = statement_timestamp(),
        lease_expires_at = statement_timestamp() + interval '10 minutes'
    from due
    where queue.id = due.id
    returning queue.id, queue.bucket_id, queue.storage_path
  )
  select claimed.id, claimed.bucket_id, claimed.storage_path
  from claimed
  order by claimed.id;
end;
$$;

create function private.complete_chat_media_cleanup(queue_ids uuid[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update private.chat_media_cleanup_queue queue
  set deleted_at = statement_timestamp(),
      lease_expires_at = null,
      next_attempt_at = statement_timestamp(),
      last_error = null
  where queue.id = any(coalesce(queue_ids, '{}'::uuid[]))
    and queue.deleted_at is null;
$$;

create function private.defer_chat_media_cleanup(
  queue_ids uuid[],
  failure_message text
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update private.chat_media_cleanup_queue queue
  set lease_expires_at = null,
      next_attempt_at = statement_timestamp() + least(
        (2 ^ least(queue.attempts, 10)) * interval '1 minute',
        interval '24 hours'
      ),
      last_error = left(coalesce(failure_message, 'storage_cleanup_failed'), 500)
  where queue.id = any(coalesce(queue_ids, '{}'::uuid[]))
    and queue.deleted_at is null;
$$;

-- The edge worker has a service-role key, but it can only call functions in
-- an exposed schema.  These invoker wrappers remain inaccessible to clients.
create function public.claim_chat_media_cleanup_batch(
  requested_batch_size integer default 1000
)
returns table (
  id uuid,
  bucket_id text,
  storage_path text
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.claim_chat_media_cleanup_batch(requested_batch_size);
$$;

create function public.complete_chat_media_cleanup(queue_ids uuid[])
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.complete_chat_media_cleanup(queue_ids);
$$;

create function public.defer_chat_media_cleanup(
  queue_ids uuid[],
  failure_message text
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.defer_chat_media_cleanup(queue_ids, failure_message);
$$;

-- Deletes at most 200 messages and 10 conversations per invocation.  Media
-- is queued before any cascading database delete, making Storage cleanup
-- resilient to worker failures and safe to retry.
create function private.finalize_expired_chat_content(
  maximum_messages integer default 200,
  maximum_conversations integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_message_limit integer := least(greatest(coalesce(maximum_messages, 200), 1), 500);
  normalized_conversation_limit integer := least(greatest(coalesce(maximum_conversations, 10), 1), 25);
  due_message_ids uuid[] := '{}'::uuid[];
  candidate_conversation record;
  deleted_message_count integer := 0;
  deleted_conversation_count integer := 0;
  queued_media_count integer := 0;
  inserted_media_count integer := 0;
begin
  -- A message is eligible if it was recalled for everyone, or every current
  -- conversation participant has hidden it and each hiding period has elapsed.
  with due_global as (
    select message.id
    from public.messages message
    where message.deleted_for_everyone_at is not null
      and message.deleted_for_everyone_at <= statement_timestamp() - interval '90 days'
    order by message.deleted_for_everyone_at, message.id
    limit normalized_message_limit
  ), due_hidden_for_everyone as (
    select hidden.message_id
    from public.message_hidden_for_users hidden
    join public.messages message on message.id = hidden.message_id
    join public.conversation_members member
      on member.conversation_id = message.conversation_id
     and member.user_id = hidden.user_id
    where message.deleted_for_everyone_at is null
      and hidden.hidden_at <= statement_timestamp() - interval '90 days'
    group by hidden.message_id, message.conversation_id
    having count(*) = (
      select count(*)
      from public.conversation_members all_members
      where all_members.conversation_id = message.conversation_id
    )
    order by min(hidden.hidden_at), hidden.message_id
    limit normalized_message_limit
  ), candidate_ids as (
    select id from due_global
    union
    select message_id as id from due_hidden_for_everyone
    limit normalized_message_limit
  ), locked_messages as (
    select message.id
    from public.messages message
    join candidate_ids candidate on candidate.id = message.id
    order by message.id
    for update of message skip locked
  )
  select coalesce(array_agg(locked_messages.id), '{}'::uuid[])
  into due_message_ids
  from locked_messages;

  if cardinality(due_message_ids) > 0 then
    insert into private.chat_media_cleanup_queue (bucket_id, storage_path)
    select
      case attachment.kind
        when 'image' then 'chat-images'
        when 'audio' then 'chat-audio'
      end,
      attachment.storage_path
    from public.message_attachments attachment
    where attachment.message_id = any(due_message_ids)
    on conflict (bucket_id, storage_path) do nothing;
    get diagnostics inserted_media_count = row_count;
    queued_media_count := queued_media_count + inserted_media_count;

    delete from public.messages message
    where message.id = any(due_message_ids);
    get diagnostics deleted_message_count = row_count;
  end if;

  -- A direct conversation is reclaimable only after both memberships have
  -- remained hidden for the full retention period.  Locking the parent row
  -- prevents a concurrent new message from being silently cascaded away.
  for candidate_conversation in
    select conversation.id
    from public.conversations conversation
    where not exists (
      select 1
      from public.conversation_members member
      where member.conversation_id = conversation.id
        and (
          member.hidden_at is null
          or member.hidden_at > statement_timestamp() - interval '90 days'
        )
    )
    and 2 = (
      select count(*)
      from public.conversation_members member
      where member.conversation_id = conversation.id
    )
    order by conversation.id
    limit normalized_conversation_limit
    for update skip locked
  loop
    -- Recheck after acquiring the parent-row lock.  A newly sent message
    -- clears both hidden_at values before this deletion can commit.
    if exists (
      select 1
      from public.conversation_members member
      where member.conversation_id = candidate_conversation.id
        and (
          member.hidden_at is null
          or member.hidden_at > statement_timestamp() - interval '90 days'
        )
    ) then
      continue;
    end if;

    insert into private.chat_media_cleanup_queue (bucket_id, storage_path)
    select
      case attachment.kind
        when 'image' then 'chat-images'
        when 'audio' then 'chat-audio'
      end,
      attachment.storage_path
    from public.message_attachments attachment
    join public.messages message on message.id = attachment.message_id
    where message.conversation_id = candidate_conversation.id
    on conflict (bucket_id, storage_path) do nothing;
    get diagnostics inserted_media_count = row_count;
    queued_media_count := queued_media_count + inserted_media_count;

    delete from public.conversations conversation
    where conversation.id = candidate_conversation.id;
    get diagnostics inserted_media_count = row_count;
    deleted_conversation_count := deleted_conversation_count + inserted_media_count;
  end loop;

  return jsonb_build_object(
    'deleted_messages', deleted_message_count,
    'deleted_conversations', deleted_conversation_count,
    'queued_media', queued_media_count
  );
end;
$$;

revoke all on function private.claim_chat_media_cleanup_batch(integer)
  from public, anon, authenticated;
revoke all on function private.complete_chat_media_cleanup(uuid[])
  from public, anon, authenticated;
revoke all on function private.defer_chat_media_cleanup(uuid[], text)
  from public, anon, authenticated;
revoke all on function private.finalize_expired_chat_content(integer, integer)
  from public, anon, authenticated;
revoke all on function public.claim_chat_media_cleanup_batch(integer)
  from public, anon, authenticated;
revoke all on function public.complete_chat_media_cleanup(uuid[])
  from public, anon, authenticated;
revoke all on function public.defer_chat_media_cleanup(uuid[], text)
  from public, anon, authenticated;

grant execute on function private.claim_chat_media_cleanup_batch(integer)
  to service_role;
grant execute on function private.complete_chat_media_cleanup(uuid[])
  to service_role;
grant execute on function private.defer_chat_media_cleanup(uuid[], text)
  to service_role;
grant execute on function private.finalize_expired_chat_content(integer, integer)
  to service_role;
grant execute on function public.claim_chat_media_cleanup_batch(integer)
  to service_role;
grant execute on function public.complete_chat_media_cleanup(uuid[])
  to service_role;
grant execute on function public.defer_chat_media_cleanup(uuid[], text)
  to service_role;

do $$
declare
  existing_job_id bigint;
begin
  if to_regclass('cron.job') is not null then
    select jobid into existing_job_id
    from cron.job
    where jobname = 'finalize-expired-chat-content';

    if existing_job_id is null then
      perform cron.schedule(
        'finalize-expired-chat-content',
        '37 * * * *',
        'select private.finalize_expired_chat_content(200, 10)'
      );
    else
      perform cron.alter_job(
        existing_job_id,
        schedule => '37 * * * *',
        command => 'select private.finalize_expired_chat_content(200, 10)'
      );
    end if;
  end if;
exception
  when insufficient_privilege then
    raise notice 'Skipping chat-content cleanup cron update; update it with database owner privileges';
end;
$$;

-- Run the shared Storage worker after the database finalizer.  This keeps the
-- existing single hourly invocation (no additional client or worker traffic)
-- while allowing newly queued chat media to be removed in the same cycle.
do $$
declare
  existing_job_id bigint;
  cleanup_command text := $job$
    select net.http_post(
      url := config.project_url || '/functions/v1/cleanup-finalized-profile-media',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', config.scheduler_token
      ),
      body := '{}'::jsonb
    )
    from (
      select
        max(secret.decrypted_secret) filter (
          where secret.name = 'account_deletion_cleanup_project_url'
        ) as project_url,
        max(secret.decrypted_secret) filter (
          where secret.name = 'account_deletion_cleanup_scheduler_token'
        ) as scheduler_token
      from vault.decrypted_secrets secret
      where secret.name in (
        'account_deletion_cleanup_project_url',
        'account_deletion_cleanup_scheduler_token'
      )
    ) config
    where config.project_url is not null
      and config.scheduler_token is not null;
  $job$;
begin
  if to_regclass('cron.job') is not null then
    select jobid into existing_job_id
    from cron.job
    where jobname = 'cleanup-finalized-profile-media';

    if existing_job_id is null then
      perform cron.schedule(
        'cleanup-finalized-profile-media',
        '43 * * * *',
        cleanup_command
      );
    else
      perform cron.alter_job(
        existing_job_id,
        schedule => '43 * * * *',
        command => cleanup_command
      );
    end if;
  end if;
exception
  when insufficient_privilege then
    raise notice 'Skipping shared media-cleanup cron update; update it with database owner privileges';
end;
$$;
