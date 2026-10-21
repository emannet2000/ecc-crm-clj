const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.join(__dirname,'../web/dist');
test('manifest and install assets are shipped',()=>{
 const m=JSON.parse(fs.readFileSync(path.join(root,'manifest.webmanifest')));
 assert.equal(m.display,'standalone'); assert.equal(m.scope,'/');
 for(const icon of m.icons){
  const bytes=fs.readFileSync(path.join(root,icon.src));
  assert.equal(bytes.readUInt32BE(16),Number(icon.sizes.split('x')[0]));
 }
 assert.match(fs.readFileSync(path.join(root,'index.html'),'utf8'),/rel="manifest"/);
});
test('service worker never intercepts private data and provides offline navigation',async()=>{
 const events={},cached=[],deleted=[];
 const offline={offline:true};
 const context={URL,Promise,self:{location:{origin:'https://crm.example'},clients:{claim:async()=>{}},addEventListener:(name,handler)=>events[name]=handler},caches:{open:async()=>({addAll:async urls=>cached.push(...urls)}),keys:async()=>['ecc-public-offline-old','unrelated'],delete:async key=>deleted.push(key),match:async()=>offline},fetch:async()=>{throw Error('offline')}};
 vm.runInNewContext(fs.readFileSync(path.join(root,'sw.js'),'utf8'),context);
 await new Promise((resolve,reject)=>events.install({waitUntil:p=>p.then(resolve,reject)}));
 assert.deepEqual(cached,['/offline.html','/icons/icon-192.png','/icons/icon-512.png']);
 await new Promise((resolve,reject)=>events.activate({waitUntil:p=>p.then(resolve,reject)}));
 assert.deepEqual(deleted,['ecc-public-offline-old']);
 for(const [url,method] of [['/api/clients','GET'],['/api/documents/1/download','GET'],['/api/auth/login','POST'],['/leads','POST'],['https://other.example/','GET']]){
  events.fetch({request:{url:new URL(url,'https://crm.example').href,method,mode:'navigate'},respondWith:()=>assert.fail('private request intercepted')});
 }
 let response;
 events.fetch({request:{url:'https://crm.example/clients/1',method:'GET',mode:'navigate'},respondWith:p=>response=p});
 assert.equal(await response,offline);
});
