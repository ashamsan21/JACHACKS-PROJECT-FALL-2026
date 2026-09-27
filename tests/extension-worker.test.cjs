const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
function worker(fetchImpl=async()=>({ok:true,json:async()=>({protocol:1})})){
  const handlers={}, calls=[];
  const chrome={runtime:{id:'a'.repeat(32),onMessage:{addListener:fn=>handlers.message=fn}},action:{onClicked:{addListener:fn=>handlers.click=fn},setBadgeText:async()=>{},setTitle:async()=>{}},scripting:{executeScript:async options=>calls.push(options)}};
  vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../extension/worker.js'),'utf8'),{chrome,URL,AbortSignal,fetch:fetchImpl});
  return {handlers,calls};
}
const sender={id:'a'.repeat(32),frameId:0,url:'https://chatgpt.com/c/example',tab:{id:1}};
test('toolbar injection is restricted to ChatGPT HTTPS',async()=>{
  const w=worker();await w.handlers.click({id:1,url:'https://evil.test'});assert.equal(w.calls.length,0);
  await w.handlers.click({id:1,url:'https://chatgpt.com.evil.test'});assert.equal(w.calls.length,0);
  await w.handlers.click({id:1,url:'https://chatgpt.com/'});assert.equal(w.calls.length,1);
});
test('messages reject unrelated pages, frames, and extension identities',()=>{
  const w=worker(); const msg={type:'promptzero.review',prompt:'hello'};
  for(const s of [{...sender,id:'b'.repeat(32)},{...sender,url:'https://evil.test'},{...sender,frameId:1}])assert.equal(w.handlers.message(msg,s,()=>assert.fail()),false);
});
test('only current draft is forwarded to the fixed endpoint',async()=>{
  let captured;
  const w=worker(async(url,options)=>{captured={url,options};return{ok:true,json:async()=>({protocol:1})};});
  const response=await new Promise(resolve=>w.handlers.message({type:'promptzero.review',prompt:'Please explain gravity.',url:'http://evil.test',history:['secret']},sender,resolve));
  assert.equal(response.data.protocol,1);assert.equal(captured.url,'http://127.0.0.1:8000/api/extension/review');
  assert.deepEqual(JSON.parse(captured.options.body),{prompt:'Please explain gravity.',budget:1024,protocol:1});
  assert.equal(captured.options.credentials,'omit');assert.equal(captured.options.redirect,'error');
});
test('empty and oversized drafts never reach the backend',()=>{
  const w=worker(()=>assert.fail('unexpected fetch'));
  for(const prompt of ['', 'x'.repeat(20001)])w.handlers.message({type:'promptzero.review',prompt},sender,response=>assert.ok(response.error));
});
test('offline backend returns actionable guidance',async()=>{
  const w=worker(async()=>{throw new TypeError('Failed to fetch');});
  const response=await new Promise(resolve=>w.handlers.message({type:'promptzero.review',prompt:'hello'},sender,resolve));
  assert.match(response.error,/run.sh/);
});
