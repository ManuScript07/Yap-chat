-- Disposable local test for the ID-only visibility query used by cached pages.
begin;

insert into auth.users (id, is_sso_user, is_anonymous, raw_user_meta_data)
values
  ('57000000-0000-0000-0000-000000000001', false, false, '{}'::jsonb),
  ('57000000-0000-0000-0000-000000000002', false, false, '{}'::jsonb),
  ('57000000-0000-0000-0000-000000000003', false, false, '{}'::jsonb);

insert into public.conversations (id, user_one_id, user_two_id, created_by)
values (
  '58000000-0000-0000-0000-000000000001',
  '57000000-0000-0000-0000-000000000001',
  '57000000-0000-0000-0000-000000000002',
  '57000000-0000-0000-0000-000000000001'
);
insert into public.conversation_members (conversation_id, user_id)
values
  ('58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000001'),
  ('58000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000002');
insert into public.messages (id, conversation_id, sender_id, type, text, created_at)
select
  ('59000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  '58000000-0000-0000-0000-000000000001',
  '57000000-0000-0000-0000-000000000001',
  'text', i::text, '2026-01-01 00:00:00+00'::timestamptz + i * interval '1 second'
from generate_series(1, 3) i;

insert into public.message_hidden_for_users (message_id, user_id)
values ('59000000-0000-0000-0000-000000000002', '57000000-0000-0000-0000-000000000001');
update public.messages set deleted_for_everyone_at = statement_timestamp()
where id = '59000000-0000-0000-0000-000000000003';

select set_config('request.jwt.claim.sub', '57000000-0000-0000-0000-000000000001', true);
set local role authenticated;
do $$
begin
  if (select count(*) from public.messages
      where conversation_id = '58000000-0000-0000-0000-000000000001'
        and id = any(array[
          '59000000-0000-0000-0000-000000000001'::uuid,
          '59000000-0000-0000-0000-000000000002'::uuid,
          '59000000-0000-0000-0000-000000000003'::uuid
        ])) <> 1 then
    raise exception 'Owner sees a hidden or globally deleted cached ID';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '57000000-0000-0000-0000-000000000002', true);
set local role authenticated;
do $$
begin
  if (select count(*) from public.messages
      where conversation_id = '58000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'Personal hide leaked to the other member';
  end if;
end;
$$;

reset role;
update public.conversation_members set cleared_at = '2026-01-02 00:00:00+00'
where conversation_id = '58000000-0000-0000-0000-000000000001'
  and user_id = '57000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', '57000000-0000-0000-0000-000000000001', true);
set local role authenticated;
do $$
begin
  if exists (select 1 from public.messages
      where conversation_id = '58000000-0000-0000-0000-000000000001') then
    raise exception 'Cleared cached IDs remained visible';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '57000000-0000-0000-0000-000000000003', true);
set local role authenticated;
do $$
begin
  if exists (select 1 from public.messages
      where conversation_id = '58000000-0000-0000-0000-000000000001') then
    raise exception 'Nonmember could inspect cached message IDs';
  end if;
end;
$$;

rollback;
