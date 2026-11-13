// Analysis only. Existing local functions; rollback-only fixtures, no migrations.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

function sql(source, timeout=150000) {
  const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{
    input:`set statement_timeout='120s';\n${source}`,encoding:'utf8',timeout,maxBuffer:16*1024*1024,
  });
  assert.equal(r.status,0,r.stderr||String(r.error));return r;
}
const counts=()=>sql(`select jsonb_build_object('users',(select count(*) from auth.users),'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages),'receipts',(select count(*) from public.message_receipts));`).stdout.trim();
const before=counts();
const owner='a7500000-0000-0000-0000-000000000001';
const definition=sql("select pg_get_functiondef('private.get_chat_summaries_impl()'::regprocedure);").stdout;
const body=definition.match(/AS \$function\$([\s\S]*?)\$function\$/i)?.[1];
assert(body,'Current SQL summary definition missing');
const rows=[];
for(const [chats,messages] of [[10,100],[100,0],[100,100],[100,1000],[1000,0],[1000,100],[1000,1000]]) {
  let source=`begin;
    insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
      select ('a7500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}'::jsonb from generate_series(1,${chats+1}) i;
    insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at)
      select ('b7500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'${owner}',
        ('a7500000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'${owner}',
        '2020-01-01'::timestamptz+i*interval '1 second' from generate_series(1,${chats}) i;
    insert into public.conversation_members(conversation_id,user_id)
      select id,user_one_id from public.conversations where id::text like 'b7500000-%'
      union all select id,user_two_id from public.conversations where id::text like 'b7500000-%';
    -- Avoid measuring fixture push/broadcast creation, not part of list reads.
    -- DDL and every fixture roll back on exit; normal triggers restored before reads.
    alter table public.messages disable trigger user;
    insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
      select ('c7500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
        ('b7500000-0000-0000-0000-'||lpad((((i-1)/greatest(${messages},1))+1)::text,12,'0'))::uuid,
        ('a7500000-0000-0000-0000-'||lpad((((i-1)/greatest(${messages},1))+2)::text,12,'0'))::uuid,
        'text','list load fixture', '2021-01-01'::timestamptz+i*interval '1 millisecond'
      from generate_series(1,${chats*messages}) i;
    alter table public.messages enable trigger user;
    do $f$begin if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
      perform private.rebuild_chat_unread_projection(array(select id from public.conversations where id::text like 'b7500000-%'));end if;end $f$;
    analyze public.conversations; analyze public.conversation_members; analyze public.profiles;
    analyze public.messages; analyze public.message_receipts;
    select set_config('request.jwt.claim.sub','${owner}',true);
  `;
  for(const state of ['unread','read']) {
    if(state==='read')source+=`insert into public.message_receipts(message_id,user_id,read_at)
      select id,'${owner}',now() from public.messages where conversation_id::text like 'b7500000-%';
      analyze public.message_receipts;`;
    for(let sample=0;sample<5;sample++)source+=`
      do $s$ declare started timestamptz:=clock_timestamp(); payload jsonb; begin
        select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into payload from public.get_chat_summaries() s;
        raise notice 'LIST_SAMPLE ${state} ${sample} % % %',
          extract(epoch from clock_timestamp()-started)*1000,jsonb_array_length(payload),octet_length(payload::text);
      end $s$;
    `;
    if(chats===1000&&messages===100)source+=`
      \\echo PLAN_${state}
      explain (analyze,buffers,format json) ${body};
      \\echo ENDPLAN_${state}
    `;
  }
  source+='rollback;';
  const result=sql(source);
  const samples=[...result.stderr.matchAll(/LIST_SAMPLE (unread|read) (\d+) ([\d.]+) (\d+) (\d+)/g)].map(m=>({state:m[1],sample:+m[2],ms:+m[3],rows:+m[4],bytes:+m[5]}));
  assert.equal(samples.length,10);
  for(const state of ['unread','read']) {
    const list=samples.filter(s=>s.state===state&&s.sample>1);
    const times=list.map(s=>s.ms).sort((a,b)=>a-b);
    const row={chats,messages_per_chat:messages,total_messages:chats*messages,state,median_ms:times[1],rows:list[0].rows,payload_bytes:list[0].bytes};
    rows.push(row);console.log(JSON.stringify(row));
    if(chats===1000&&messages===100) {
      const plan=result.stdout.match(new RegExp(`PLAN_${state}\\r?\\n([\\s\\S]*?)\\r?\\nENDPLAN_${state}`));
      assert(plan);writeFileSync(`tmp/chat_list_plan_${state}.json`,JSON.stringify(JSON.parse(plan[1]),null,2));
    }
  }
}
assert.equal(counts(),before,'Rollback fixture counts changed');
writeFileSync('tmp/chat_list_load_benchmark.json',JSON.stringify({rows,fixtures_unchanged:true},null,2));
