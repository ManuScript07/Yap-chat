// Real overlapping transactions, local Docker only. Exact ledger + totals oracle.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
const args=['exec','-i','supabase_db_Yap_chat','psql','-X','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-qAt'];
function sql(source){const r=spawnSync('docker',args,{input:`set statement_timeout='15s';${source}`,encoding:'utf8',timeout:20000});assert.equal(r.status,0,r.stderr||String(r.error));return r.stdout.trim();}
function start(source,actor,hold=false){
 const child=spawn('docker',args),application=`unread_${randomUUID().replaceAll('-','')}`;let output='',errors='',readyResolve;
 const ready=new Promise(resolve=>{readyResolve=resolve;});const timer=setTimeout(()=>child.kill(),20000);
 const done=new Promise((resolve,reject)=>{child.stdout.on('data',data=>{output+=data;if(output.includes('UNREAD_READY'))readyResolve();});child.stderr.on('data',data=>{errors+=data;});child.on('error',reject);child.on('close',code=>{clearTimeout(timer);code===0?resolve(output):reject(Error(errors||`psql exit ${code}`));});});done.catch(()=>{});
 const body=`set application_name='${application}';set statement_timeout='10s';set lock_timeout='5s';set idle_in_transaction_session_timeout='10s';begin;select set_config('request.jwt.claim.sub','${actor}',true);${source};\n`;
 if(hold)child.stdin.write(body);else child.stdin.end(body+'commit;');
 return{application,done,ready:hold?Promise.race([ready,done.then(()=>assert(output.includes('UNREAD_READY')))]):done,release:()=>child.stdin.end('commit;')};
}
const users=[randomUUID(),randomUUID()].sort(),chat=randomUUID(),results=[];
const snapshot=()=>sql("select jsonb_build_object('users',(select count(*)from auth.users),'chats',(select count(*)from public.conversations),'messages',(select count(*)from public.messages),'counts',(select count(*)from private.chat_unread_counts),'keys',(select count(*)from private.chat_unread_messages));");
const before=snapshot();
function verify(){
 const mismatch=sql(`with expected as(select m.id as message_id,cm.user_id,m.conversation_id,m.created_at
 from public.messages m join public.conversation_members cm on cm.conversation_id=m.conversation_id
 where m.conversation_id='${chat}' and cm.user_id<>m.sender_id and m.deleted_for_everyone_at is null
 and m.created_at>coalesce(cm.cleared_at,'-infinity'::timestamptz)
 and not exists(select 1 from public.message_receipts r where r.message_id=m.id and r.user_id=cm.user_id)
 and not exists(select 1 from public.message_hidden_for_users h where h.message_id=m.id and h.user_id=cm.user_id)),diff as(
 (select * from expected except select message_id,user_id,conversation_id,created_at from private.chat_unread_messages where conversation_id='${chat}')
 union all(select message_id,user_id,conversation_id,created_at from private.chat_unread_messages where conversation_id='${chat}' except select * from expected))
 select(select count(*)from diff)+(select count(*)from public.conversation_members cm full join private.chat_unread_counts c using(conversation_id,user_id)
 where coalesce(cm.conversation_id,c.conversation_id)='${chat}' and(c.unread_count,c.is_visible,c.is_muted)is distinct from(
 (select count(*)from expected e where e.user_id=cm.user_id),cm.hidden_at is null,cm.is_muted));`);
 assert.equal(mismatch,'0','Unread state drifted after overlapping writes');
}
try{
 sql(`begin;insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data)values('${users[0]}',false,false,'{}'),('${users[1]}',false,false,'{}');
 insert into public.conversations(id,user_one_id,user_two_id,created_by)values('${chat}','${users[0]}','${users[1]}','${users[0]}');commit;`);
 for(let round=0;round<2;round++){
  const actor=users[round],peer=users[1-round];
  for(const name of ['read_read','hide_read','read_hide','delete_read','read_delete','clear_read','read_clear','unread_physical_delete','unhide_physical_delete','opposite_readers','timestamp_update_incoming','read_incoming','incoming_read']){
   const incoming=randomUUID(),outgoing=randomUUID();
   sql(`begin;delete from public.messages where conversation_id='${chat}';
   insert into public.conversation_members(conversation_id,user_id)values('${chat}','${actor}'),('${chat}','${peer}')on conflict do nothing;
   update public.conversation_members set cleared_at=null,hidden_at=null,is_muted=false where conversation_id='${chat}';
   insert into public.messages(id,conversation_id,sender_id,type,text,created_at)values('${incoming}','${chat}','${peer}','text','incoming','2020-01-01'),('${outgoing}','${chat}','${actor}','text','outgoing','2021-01-01');commit;`);
   const receipt=`insert into public.message_receipts(message_id,user_id,read_at)values('${incoming}','${actor}',clock_timestamp())on conflict do nothing`;
   const hide=`insert into public.message_hidden_for_users(message_id,user_id)values('${incoming}','${actor}')on conflict do nothing`;
   const deleted=`update public.messages set deleted_for_everyone_at=clock_timestamp()where id='${incoming}'`;
   const clear=`update public.conversation_members set cleared_at=clock_timestamp()where conversation_id='${chat}'and user_id='${actor}'`;
   const send=`insert into public.messages(id,conversation_id,sender_id,type,text)values('${randomUUID()}','${chat}','${peer}','text','new incoming')`;
   let first,second,independent=false;
   if(name==='read_read'){first=receipt;second=receipt;}
   if(name==='hide_read'){first=hide;second=receipt;}
   if(name==='read_hide'){first=receipt;second=hide;}
   if(name==='delete_read'){first=deleted;second=receipt;}
   if(name==='read_delete'){first=receipt;second=deleted;}
   if(name==='clear_read'){first=clear;second=receipt;}
   if(name==='read_clear'){first=receipt;second=clear;}
   if(name==='unread_physical_delete'){sql(receipt);first=`delete from public.message_receipts where message_id='${incoming}'and user_id='${actor}'`;second=`delete from public.messages where id='${incoming}'`;}
   if(name==='unhide_physical_delete'){sql(hide);first=`delete from public.message_hidden_for_users where message_id='${incoming}'and user_id='${actor}'`;second=`delete from public.messages where id='${incoming}'`;}
   if(name==='opposite_readers'){first=receipt;second=`insert into public.message_receipts(message_id,user_id,read_at)values('${outgoing}','${peer}',clock_timestamp())`;independent=true;}
   if(name==='timestamp_update_incoming'){sql(receipt);first=`update public.message_receipts set read_at=clock_timestamp()where message_id='${incoming}'and user_id='${actor}'`;second=send;independent=true;}
   if(name==='read_incoming'){first=`select public.mark_conversations_read(array['${chat}']::uuid[])`;second=send;}
   if(name==='incoming_read'){first=send;second=`select public.mark_conversations_read(array['${chat}']::uuid[])`;}
   const a=start(`${first};select 'UNREAD_READY'`,actor,true);await a.ready;
   const b=start(second,actor);
   try{
    if(independent)await b.done;
    else{let blocked=false;const until=Date.now()+3500;while(!blocked&&Date.now()<until){blocked=sql(`select exists(select 1 from pg_stat_activity where application_name='${b.application}'and wait_event_type='Lock');`)==='t';if(!blocked)await new Promise(resolve=>setTimeout(resolve,10));}assert(blocked,`${name} did not overlap`);}
   }finally{a.release();}
   await Promise.all([a.done,b.done]);verify();results.push({round,name,overlap_verified:true,passed:true});
  }
 }
 const report={passed:true,pairs:results.length,transactions:results.length*2,scenarios:results};writeFileSync('tmp/chat_unread_concurrency.json',JSON.stringify(report,null,2));console.log(JSON.stringify({passed:true,pairs:results.length,transactions:results.length*2}));
}finally{
 sql(`begin;delete from public.conversations where id='${chat}';delete from public.profiles where id in('${users[0]}','${users[1]}');delete from auth.users where id in('${users[0]}','${users[1]}');commit;`);assert.equal(snapshot(),before,'Fixture cleanup mismatch');
}
