-- Local Supabase only. Fixtures and events are rolled back.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
 ('a5000000-0000-0000-0000-000000000001',false,false,'{}'),
 ('a5000000-0000-0000-0000-000000000002',false,false,'{}');
insert into public.conversations(id,user_one_id,user_two_id,created_by) values
 ('a5100000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000002','a5000000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id,user_id) values
 ('a5100000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001'),
 ('a5100000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000002');
insert into public.messages(id,conversation_id,sender_id,type,text) values
 ('a5200000-0000-0000-0000-000000000001','a5100000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','text','chronology test');
create function pg_temp.assert_order(expected jsonb, expected_version bigint) returns void
language plpgsql as $$ declare state jsonb; begin
 state := private.message_reaction_state('a5200000-0000-0000-0000-000000000001');
 if state->'reactions' <> expected or (state->>'version')::bigint <> expected_version then
  raise exception 'Incorrect chronological state: %', state;
 end if;
end $$;

-- The larger UUID reacts first. UUID order must not override chronology.
select set_config('request.jwt.claim.sub','a5000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.set_message_reaction('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001','heart',gen_random_uuid(),0);
reset role;
select set_config('request.jwt.claim.sub','a5000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.set_message_reaction('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001','heart',gen_random_uuid(),0);
reset role;
select pg_temp.assert_order('[{"user_id":"a5000000-0000-0000-0000-000000000002","code":"heart","position":1},{"user_id":"a5000000-0000-0000-0000-000000000001","code":"heart","position":2}]',2);

-- Replacement retains the first participant's position; revisions still grow.
update private.message_reactions set updated_at=statement_timestamp()-interval '1 second' where message_id='a5200000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','a5000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.set_message_reaction('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001','fire',gen_random_uuid(),1);
reset role;
select pg_temp.assert_order('[{"user_id":"a5000000-0000-0000-0000-000000000002","code":"fire","position":1},{"user_id":"a5000000-0000-0000-0000-000000000001","code":"heart","position":2}]',3);

-- Removal and re-addition move that participant to the end.
update private.message_reactions set updated_at=statement_timestamp()-interval '1 second' where message_id='a5200000-0000-0000-0000-000000000001';
set local role authenticated;
select public.set_message_reaction('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001',null,gen_random_uuid(),3);
reset role;
update private.message_reactions set updated_at=statement_timestamp()-interval '1 second' where message_id='a5200000-0000-0000-0000-000000000001';
set local role authenticated;
select public.set_message_reaction('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001','fire',gen_random_uuid(),4);
reset role;
select pg_temp.assert_order('[{"user_id":"a5000000-0000-0000-0000-000000000001","code":"heart","position":2},{"user_id":"a5000000-0000-0000-0000-000000000002","code":"fire","position":5}]',5);

-- Same emoji can merge without changing avatar chronology.
update private.message_reactions set updated_at=statement_timestamp()-interval '1 second' where message_id='a5200000-0000-0000-0000-000000000001';
set local role authenticated;
select public.set_message_reaction('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001','heart',gen_random_uuid(),5);
select public.set_message_reaction('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001','heart',gen_random_uuid(),6);
do $$ declare expected jsonb; begin
 expected := '[{"user_id":"a5000000-0000-0000-0000-000000000001","code":"heart","position":2},{"user_id":"a5000000-0000-0000-0000-000000000002","code":"heart","position":5}]';
 if (select reaction_state->'reactions' from public.get_conversation_messages('a5100000-0000-0000-0000-000000000001') where id='a5200000-0000-0000-0000-000000000001') <> expected then raise exception 'Page lost order'; end if;
 if (select reaction_state->'reactions' from public.get_conversation_message_window('a5100000-0000-0000-0000-000000000001','a5200000-0000-0000-0000-000000000001') where id='a5200000-0000-0000-0000-000000000001') <> expected then raise exception 'Window lost order'; end if;
 if (select reaction_state->'reactions' from public.get_visible_conversation_message_states('a5100000-0000-0000-0000-000000000001',array['a5200000-0000-0000-0000-000000000001']::uuid[])) <> expected then raise exception 'Cached page lost order'; end if;
end $$;
reset role;
select pg_temp.assert_order('[{"user_id":"a5000000-0000-0000-0000-000000000001","code":"heart","position":2},{"user_id":"a5000000-0000-0000-0000-000000000002","code":"heart","position":5}]',6);
do $$ begin
 if (select count(*) from realtime.messages where payload->>'reason'='reaction_changed' and payload->>'message_id'='a5200000-0000-0000-0000-000000000001') <> 12 then raise exception 'Unexpected broadcast count'; end if;
 if (select count(*) from public.push_notification_outbox where reaction_message_id='a5200000-0000-0000-0000-000000000001') <> 1 then raise exception 'Unexpected push count'; end if;
end $$;
rollback;
