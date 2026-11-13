// Local rollback-only before/after summary work. No remote endpoint or reset.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
function sql(source) {
  const r=spawnSync('docker',['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'],{
    input:`set statement_timeout='120s';\n${source}`,encoding:'utf8',timeout:180000,maxBuffer:12*1024*1024,
  });
  assert.equal(r.status,0,r.stderr||String(r.error));return r;
}
const counts=()=>sql("select jsonb_build_object('users',(select count(*) from auth.users),'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages),'receipts',(select count(*) from public.message_receipts));").stdout.trim();
const before=counts();const results=[];
const smallOnly=process.env.TARGETED_CHAT_SMALL_ONLY==='1';
const owner='a8520000-0000-0000-0000-000000000001';
const id=i=>`b8520000-0000-0000-0000-${String(i).padStart(12,'0')}`;
const def=sql("select pg_get_functiondef('private.get_chat_summaries_by_ids_impl(uuid[])'::regprocedure);").stdout;
const body=def.match(/return query\s+([\s\S]*?);\s*end;/i)?.[1];assert(body);
for(const [chats,messages] of (smallOnly?[[100,1000]]:[[100,1000],[1000,100],[1000,1000]])) {
  let source=`begin;
    insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)
    select ('a8520000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,false,'{}' from generate_series(1,${chats+1}) i;
    insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at)
    select ('b8520000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'${owner}',
      ('a8520000-0000-0000-0000-'||lpad((i+1)::text,12,'0'))::uuid,'${owner}',
      '2020-01-01'::timestamptz+i*interval '1 second' from generate_series(1,${chats}) i;
    insert into public.conversation_members(conversation_id,user_id)
    select id,user_one_id from public.conversations where id::text like 'b8520000-%'
    union all select id,user_two_id from public.conversations where id::text like 'b8520000-%';
    alter table public.messages disable trigger user;
    insert into public.messages(id,conversation_id,sender_id,type,text,created_at)
    select ('c8520000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
      ('b8520000-0000-0000-0000-'||lpad((((i-1)/${messages})+1)::text,12,'0'))::uuid,
      ('a8520000-0000-0000-0000-'||lpad((((i-1)/${messages})+2)::text,12,'0'))::uuid,
      'text','targeted summary fixture','2021-01-01'::timestamptz+i*interval '1 millisecond'
    from generate_series(1,${chats*messages}) i;
    alter table public.messages enable trigger user;
    do $f$begin if to_regprocedure('private.rebuild_chat_unread_projection(uuid[])')is not null then
      perform private.rebuild_chat_unread_projection(array(select id from public.conversations where id::text like 'b8520000-%'));end if;end $f$;
    analyze public.conversation_members;analyze public.messages;analyze public.profiles;analyze public.conversations;analyze public.message_receipts;
    select set_config('request.jwt.claim.sub','${owner}',true);
  `;
  for(const state of ['unread','read']) {
    if(state==='read')source+=`insert into public.message_receipts(message_id,user_id,read_at)
      select id,'${owner}',now() from public.messages where conversation_id::text like 'b8520000-%'; analyze public.message_receipts;`;
    for(const size of [0,1,10,50]) {
      const ids=`array[${Array.from({length:Math.max(size,1)},(_,i)=>`'${id(i+1)}'`).join(',')}]::uuid[]`;
      const call=size===0?'public.get_chat_summaries()':`public.get_chat_summaries_by_ids(${ids})`;
      for(let sample=0;sample<5;sample++)source+=`
        do $b$ declare started timestamptz:=clock_timestamp(); payload jsonb; begin
          select jsonb_agg(to_jsonb(s)) into payload from ${call} s;
          raise notice 'TARGET_SAMPLE ${state} ${size} ${sample} % % %',
            extract(epoch from clock_timestamp()-started)*1000,jsonb_array_length(payload),octet_length(payload::text);
        end $b$;`;
      if(chats===1000&&messages===1000&&size===1) {
        const query=body.replaceAll(/\bactor\b/g,`'${owner}'::uuid`).replaceAll(/\bconversation_ids\b/g,ids);
        source+=`\n\\echo PLAN_${state}\nexplain(analyze,buffers,format json) ${query};\n\\echo ENDPLAN_${state}\n`;
      }
      if(smallOnly&&state==='read'&&size===50) {
        const query=body.replaceAll(/\bactor\b/g,()=>'$1').replaceAll(/\bconversation_ids\b/g,()=>'$2');
        source+=`\nset plan_cache_mode=force_generic_plan;
          prepare targeted_plan(uuid,uuid[]) as ${query};
          \\echo GENERIC_PLAN
          explain(analyze,buffers,format json) execute targeted_plan('${owner}',${ids});
          \\echo END_GENERIC_PLAN\n`;
      }
    }
  }
  source+='rollback;';const r=sql(source);
  const samples=[...r.stderr.matchAll(/TARGET_SAMPLE (unread|read) (\d+) (\d+) ([\d.]+) (\d+) (\d+)/g)];assert.equal(samples.length,40);
  for(const state of ['unread','read'])for(const size of [0,1,10,50]) {
    const selected=samples.filter(m=>m[1]===state&&+m[2]===size&&+m[3]>=2);
    const times=selected.map(m=>+m[4]).sort((a,b)=>a-b);
    const row={chats,messages_per_chat:messages,state,batch_size:size||'full',median_ms:times[1],rows:+selected[0][5],bytes:+selected[0][6]};
    assert.equal(row.rows,size||chats);results.push(row);console.log(JSON.stringify(row));
  }
  if(chats===1000&&messages===1000)for(const state of ['unread','read']) {
    const match=r.stdout.match(new RegExp(`PLAN_${state}\\r?\\n([\\s\\S]*?)\\r?\\nENDPLAN_${state}`));assert(match);
    writeFileSync(`tmp/targeted_chat_plan_${state}.json`,JSON.stringify(JSON.parse(match[1]),null,2));
  }
  if(smallOnly) {
    const match=r.stdout.match(/GENERIC_PLAN\r?\n([\s\S]*?)\r?\nEND_GENERIC_PLAN/);assert(match);
    writeFileSync('tmp/targeted_chat_generic_plan.json',JSON.stringify(JSON.parse(match[1]),null,2));
  }
}
assert.equal(counts(),before,'Benchmark fixtures changed');
writeFileSync(smallOnly?'tmp/targeted_chat_small_benchmark.json':'tmp/targeted_chat_summary_benchmark.json',JSON.stringify({results,fixtures_unchanged:true},null,2));
