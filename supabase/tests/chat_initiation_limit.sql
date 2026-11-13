-- Existing product limit, authenticated API, no fixture survives rollback.
begin;
insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
select ('a8970000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}'
from generate_series(1,111)i;

-- A has 99 incoming visible chats and one hidden chat; B already has 100.
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select ('b8970000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'a8970000-0000-0000-0000-000000000001',
 ('a8970000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 ('a8970000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid
from generate_series(10,108)i;
insert into public.conversations(id,user_one_id,user_two_id,created_by)
select ('c8970000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 'a8970000-0000-0000-0000-000000000002',
 ('a8970000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
 ('a8970000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid
from generate_series(10,109)i;
insert into public.conversations(id,user_one_id,user_two_id,created_by) values
('b8970000-0000-0000-0000-000000000110','a8970000-0000-0000-0000-000000000001','a8970000-0000-0000-0000-000000000110','a8970000-0000-0000-0000-000000000001');
insert into public.conversation_members(conversation_id,user_id)
select id,user_one_id from public.conversations where id::text like 'b8970000-%' or id::text like 'c8970000-%'
union all select id,user_two_id from public.conversations where id::text like 'b8970000-%' or id::text like 'c8970000-%';
update public.conversation_members set hidden_at=now(),cleared_at='2020-01-01'
where conversation_id='b8970000-0000-0000-0000-000000000110' and user_id='a8970000-0000-0000-0000-000000000001';

create function pg_temp.expect_limit(peer uuid) returns void language plpgsql as $$begin
 begin perform public.create_direct_conversation(peer);raise exception 'Limit was not enforced';
 exception when sqlstate 'P0001' then if sqlerrm<>'chat_limit_reached' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','a8970000-0000-0000-0000-000000000001',true);
set local role authenticated;
-- 99 -> 100 succeeds even though B already has 100 visible incoming chats.
select public.create_direct_conversation('a8970000-0000-0000-0000-000000000002');
select pg_temp.expect_limit('a8970000-0000-0000-0000-000000000003');
select pg_temp.expect_limit('a8970000-0000-0000-0000-000000000110');
reset role;
do $$begin
 if(select count(*)from public.conversation_members where user_id='a8970000-0000-0000-0000-000000000001' and hidden_at is null)<>100
 or(select count(*)from public.conversation_members where user_id='a8970000-0000-0000-0000-000000000002' and hidden_at is null)<>101 then
 raise exception 'Wrong boundary or recipient cap applied';end if;
end$$;

update public.conversation_members set hidden_at=now(),cleared_at='2020-01-01'
where conversation_id='b8970000-0000-0000-0000-000000000010' and user_id='a8970000-0000-0000-0000-000000000001';
set local role authenticated;
do $$declare actual uuid;begin
 actual:=public.create_direct_conversation('a8970000-0000-0000-0000-000000000110');
 if actual<>'b8970000-0000-0000-0000-000000000110'::uuid then raise exception 'Reopen created a duplicate';end if;
end$$;
reset role;
do $$begin
 if(select cleared_at from public.conversation_members where user_id='a8970000-0000-0000-0000-000000000001' and conversation_id='b8970000-0000-0000-0000-000000000110')<>'2020-01-01'::timestamptz then raise exception 'Reopen lost clear cutoff';end if;
end$$;

-- New incoming and incoming restoration remain available above the limit.
select set_config('request.jwt.claim.sub','a8970000-0000-0000-0000-000000000003',true);
set local role authenticated;
do $$declare chat uuid;begin
 chat:=public.create_direct_conversation('a8970000-0000-0000-0000-000000000001');
 perform public.send_chat_message(extensions.gen_random_uuid(),chat,'text','new incoming beyond limit');
end$$;
reset role;
select set_config('request.jwt.claim.sub','a8970000-0000-0000-0000-000000000010',true);
set local role authenticated;
select public.send_chat_message(extensions.gen_random_uuid(),'b8970000-0000-0000-0000-000000000010','text','restore incoming beyond limit');
reset role;
select set_config('request.jwt.claim.sub','a8970000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.create_direct_conversation('a8970000-0000-0000-0000-000000000002');
select pg_temp.expect_limit('a8970000-0000-0000-0000-000000000111');
reset role;
do $$begin
 if(select count(*)from public.conversation_members where user_id='a8970000-0000-0000-0000-000000000001' and hidden_at is null)<>102 then raise exception 'Incoming restoration was blocked at cap';end if;
 if(select count(*)from public.messages where text in('new incoming beyond limit','restore incoming beyond limit') and sender_id::text like 'a8970000-%')<>2 then raise exception 'Incoming delivery failed';end if;
end$$;
rollback;
