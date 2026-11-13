// Concurrent committed transactions on random LOCAL fixtures, never production.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
const args=['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'];
function sql(source){const r=spawnSync('docker',args,{input:`set statement_timeout='15s';${source}`,encoding:'utf8',timeout:20000});assert.equal(r.status,0,r.stderr||String(r.error));return r.stdout.trim();}
function start(source,expectReady=false){
 const child=spawn('docker',args);let output='',errors='',readyResolve;
 const application=`catalog_test_${randomUUID().replaceAll('-','')}`;
 const ready=new Promise(resolve=>{readyResolve=resolve;});
 const timer=setTimeout(()=>child.kill(),20000);
 const done=new Promise((resolve,reject)=>{
 child.stdout.on('data',data=>{output+=data;if(output.includes('CATALOG_READY'))readyResolve();});
 child.stderr.on('data',data=>{errors+=data;});child.on('error',reject);
 child.on('close',code=>{clearTimeout(timer);code===0?resolve(output):reject(Error(errors||`exit ${code}`));});
 });done.catch(()=>{});
 const body=`set application_name='${application}';set statement_timeout='10s';set lock_timeout='5s';set idle_in_transaction_session_timeout='10s';begin;${source};\n`;
 if(expectReady) child.stdin.write(body); else child.stdin.end(body+'commit;');
 return{application,release:()=>child.stdin.end('commit;'),ready:expectReady?Promise.race([ready,done.then(()=>{assert(output.includes('CATALOG_READY'),'missing writer marker');})]):done,done};
}
const users=[randomUUID(),randomUUID(),randomUUID()].sort(),chat=randomUUID();
const ids=users.map(id=>`'${id}'`).join(',');
const snapshot=()=>sql("select jsonb_build_object('users',(select count(*) from auth.users),'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages),'catalog',(select count(*) from private.chat_list_catalog));");
const before=snapshot(),results=[];
function verify(){
 const mismatch=sql(`with expected as(select cm.user_id,cm.conversation_id,cm.hidden_at is null as is_visible,
 coalesce(m.created_at,c.created_at) as activity_at,m.id as latest_message_id
 from public.conversation_members cm join public.conversations c on c.id=cm.conversation_id
 left join lateral(select msg.id,msg.created_at from public.messages msg where cm.hidden_at is null
 and msg.conversation_id=cm.conversation_id and msg.deleted_for_everyone_at is null
 and msg.created_at>coalesce(cm.cleared_at,'-infinity'::timestamptz)
 and not exists(select 1 from public.message_hidden_for_users h where h.message_id=msg.id and h.user_id=cm.user_id)
 order by msg.created_at desc,msg.id desc limit 1)m on true where c.id='${chat}')
 select count(*) from expected e full join(select * from private.chat_list_catalog where conversation_id='${chat}')x using(user_id,conversation_id)
 where(e.activity_at,e.latest_message_id,e.is_visible)is distinct from(x.activity_at,x.latest_message_id,x.is_visible);`);
 assert.equal(mismatch,'0','Catalog diverged after committed concurrent writes');
}
try{
 sql(`begin;insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)values ${users.map(id=>`('${id}',false,false,'{}')`).join(',')};
 insert into public.conversations(id,user_one_id,user_two_id,created_by)values('${chat}','${users[0]}','${users[1]}','${users[0]}');
 insert into public.conversation_members(conversation_id,user_id)values('${chat}','${users[0]}'),('${chat}','${users[1]}');commit;`);
 for(let round=0;round<8;round++){
  const old=randomUUID(),latest=randomUUID();
  sql(`begin;delete from public.messages where conversation_id='${chat}';
  update public.conversation_members set hidden_at=null,cleared_at=null where conversation_id='${chat}';
  insert into public.messages(id,conversation_id,sender_id,type,text,created_at)values
  ('${old}','${chat}','${users[0]}','text','older','2020-01-01'),('${latest}','${chat}','${users[1]}','text','latest','2021-01-01');commit;`);
  const incoming=`insert into public.messages(id,conversation_id,sender_id,type,text,created_at)values('${randomUUID()}','${chat}','${users[1]}','text','incoming',clock_timestamp())`;
  const cases=[
   ['both_hide',`update public.conversation_members set hidden_at=clock_timestamp() where conversation_id='${chat}' and user_id='${users[0]}'`,`update public.conversation_members set hidden_at=clock_timestamp() where conversation_id='${chat}' and user_id='${users[1]}'`],
   ['hide_then_send',`update public.conversation_members set hidden_at=clock_timestamp() where conversation_id='${chat}' and user_id='${users[0]}'`,incoming],
   ['clear_then_send',`update public.conversation_members set cleared_at=clock_timestamp() where conversation_id='${chat}' and user_id='${users[0]}'`,incoming.replace('incoming','after clear')],
   ['soft_delete_then_hide',`update public.messages set deleted_for_everyone_at=clock_timestamp() where id='${latest}'`,`insert into public.message_hidden_for_users(message_id,user_id)values('${old}','${users[0]}')on conflict do nothing`],
   ['hide_then_restore',`update public.conversation_members set hidden_at=clock_timestamp() where conversation_id='${chat}' and user_id='${users[1]}'`,`update public.messages set deleted_for_everyone_at=null where id='${latest}'`],
  ];
  for(const[name,firstSql,secondSql]of cases){
   // Distinct message identity for each send scenario.
   const second=secondSql.replace(/'([0-9a-f-]{36})','([^']+)','([^']+)','text','(?:incoming|after clear)'/,()=>`'${randomUUID()}','${chat}','${users[1]}','text','concurrent send'`);
   const a=start(`${firstSql};select 'CATALOG_READY'`,true);await a.ready;
   const b=start(second);
   try {
    if(name==='both_hide'){
     // Opposite member-only changes must finish even while A holds its row.
     await b.done;
    }else{
     const end=Date.now()+3500;let blocked=false;
     while(!blocked&&Date.now()<end){
      blocked=sql(`select exists(select 1 from pg_stat_activity where application_name='${b.application}' and wait_event_type='Lock');`)==='t';
      if(!blocked)await new Promise(resolve=>setTimeout(resolve,10));
     }
     assert(blocked,`${name} did not overlap the first transaction`);
    }
   }finally{a.release();}
   await Promise.all([a.done,b.done]);verify();results.push({round,name,passed:true,overlap_verified:true});
  }
 }
 // A catalog request must not acquire both members' locks for a member-only
 // visibility change; both_hide above exercises the opposing row-lock order.
 writeFileSync('tmp/chat_list_catalog_concurrency.json',JSON.stringify({passed:true,transactions:results.length*2,scenarios:results},null,2));
 console.log(JSON.stringify({passed:true,pairs:results.length,transactions:results.length*2}));
}finally{
 sql(`begin;delete from public.conversations where id='${chat}';delete from public.profiles where id in(${ids});delete from auth.users where id in(${ids});commit;`);
 assert.equal(snapshot(),before,'Fixture cleanup changed preexisting row counts');
}
