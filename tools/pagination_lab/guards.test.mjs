import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PaginationLab,localUrl,literal,root} from './lab.mjs';
import {relative,isAbsolute} from 'node:path';

test('lab refuses remote URLs, credentials, paths and rebinding names',()=>{
  for(const value of ['https://x.supabase.co','http://192.168.1.1:54321','http://127.0.0.1.evil.test','http://user:secret@localhost:54321','http://localhost:54321/x','http://localhost:54321?url=x']) {
    assert.throws(()=>localUrl(value));
  }
  assert.equal(localUrl('http://127.0.0.1:54321'),'http://127.0.0.1:54321');
});
test('lab names cannot escape the private workspace directory',()=>{
  for(const name of ['../x','a/b','a\\b','','x;command'])assert.throws(()=>new PaginationLab(name));
  const lab=new PaginationLab('unit-test');
  const path=relative(root,lab.directory);
  assert(!isAbsolute(path)&&!path.startsWith('..'));
});
test('SQL values remain data even when they contain apostrophes',()=>{
  assert.equal(literal("a'; drop table x; --"),"'a''; drop table x; --'");
});
