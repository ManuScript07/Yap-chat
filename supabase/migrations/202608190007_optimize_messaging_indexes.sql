create index if not exists conversations_created_by_idx
on public.conversations (created_by);

create index if not exists conversations_last_message_id_idx
on public.conversations (last_message_id);

create index if not exists conversations_user_two_id_idx
on public.conversations (user_two_id);

create index if not exists messages_reply_to_message_id_idx
on public.messages (reply_to_message_id);

drop index if exists public.conversations_updated_at_idx;
