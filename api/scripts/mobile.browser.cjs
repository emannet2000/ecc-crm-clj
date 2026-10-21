const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawn}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const delay=ms=>new Promise(r=>setTimeout(r,ms));

class Browser {
  constructor(){
    this.dir=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-ui-'));
    this.child=spawn(process.env.CHROME_PATH||'/usr/lib/chromium/chromium',['--headless',...(process.env.CHROME_SINGLE_PROCESS==='1'?['--no-zygote','--single-process']:[]),'--disable-breakpad','--disable-crash-reporter','--disable-crashpad-for-testing','--no-sandbox','--disable-dev-shm-usage','--disable-gpu','--no-first-run','--disable-background-networking','--remote-debugging-pipe','--user-data-dir='+this.dir],{stdio:['ignore','ignore','pipe','pipe','pipe']});
    this.seq=0;this.pending=new Map();this.buffer='';this.errors=[];this.requests=[];this.signedIn=false;
    this.child.on('error',e=>{for(const p of this.pending.values())p.reject(e);});
    this.child.on('exit',(code,signal)=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Chromium exited '+code+' '+signal+' '+this.stderr));}this.pending.clear();});
    this.child.stderr.on('data',d=>{this.stderr=(this.stderr||'').slice(-2000)+d;});
    for(const pipe of [this.child.stdio[3],this.child.stdio[4]])pipe.on('error',e=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error(e.message+' '+this.stderr));}this.pending.clear();});
    this.child.stdio[4].on('data',d=>{this.buffer+=d.toString();let end;while((end=this.buffer.indexOf('\0'))>=0){const raw=this.buffer.slice(0,end);this.buffer=this.buffer.slice(end+1);if(!raw)continue;const msg=JSON.parse(raw);if(msg.id){const p=this.pending.get(msg.id);if(p){clearTimeout(p.timer);this.pending.delete(msg.id);msg.error?p.reject(Error(JSON.stringify(msg.error))):p.resolve(msg.result);}}else this.event(msg).catch(e=>this.errors.push(e.message));}});
  }
  send(method,params={},sessionId=this.session){return new Promise((resolve,reject)=>{const id=++this.seq;const timer=setTimeout(()=>{this.pending.delete(id);reject(Error(method+' timed out '+(this.stderr||'')));},20000);this.pending.set(id,{resolve,reject,timer});this.child.stdio[3].write(JSON.stringify({id,method,params,...(sessionId?{sessionId}: {})})+'\0');});}
  async event(msg){
    if(msg.method==='Runtime.exceptionThrown')this.errors.push(msg.params.exceptionDetails.text);
    if(msg.method!=='Fetch.requestPaused')return;
    const req=msg.params.request,url=new URL(req.url);this.requests.push(url.pathname+url.search);
    let status=200,mime='application/json',body;
    const user={id:1,name:'Alex Rivera',email:'alex@example.com',role:'admin'};
    if(url.pathname==='/api/time')body={unixMillis:Date.now(),timezone:'Asia/Manila',offsetMinutes:480,date:new Date(Date.now()+8*3600000).toISOString().slice(0,10)};
    else if(url.pathname==='/api/auth/me'){status=this.signedIn?200:401;body=this.signedIn?user:{error:'Not authenticated'};}
    else if(url.pathname==='/api/auth/login'){this.signedIn=true;body={token:'memory-only',user};}
    else if(url.pathname==='/api/auth/logout'){this.signedIn=false;body={loggedOut:true};}
    else if(url.pathname==='/api/auth/recover')body={message:'queued'};
    else if(url.pathname==='/api/contacts/check')body={matches:[]};
    else if(url.pathname==='/api/stats')body={stTotalLeads:128,stHotLeads:24,stTotalClients:42,stOpenTasks:16,stOverdueTasks:3,stStageCounts:[{scStage:'New Lead',scCount:45},{scStage:'Qualified',scCount:32},{scStage:'Proposal Sent',scCount:12}],stSourceCounts:[{srcSource:'Website',srcCount:48}],stUpcomingTasks:[],stRecentActivity:[]};
    else if(url.pathname==='/api/users')body=[user];
    else if(url.pathname==='/api/reminders')body=[{id:9,kind:'followup',title:'Follow up: Maya Chen',due:'2026-10-18',path:'/leads/1',read:false}];
    else if(url.pathname.endsWith('/read'))body={read:true};
    else if(url.pathname==='/api/archive')body=[{id:4,kind:'lead',name:'Archived contact',number:'ECC-2026-0004',date:'2026-10-16'}];
    else if(url.pathname==='/api/duplicates')body=[{field:'email',value:'maya@example.com',records:[{id:1,kind:'lead',name:'Maya Chen'},{id:2,kind:'client',name:'Maya Chen'}]}];
    else if(url.pathname==='/api/metrics')body=[{pendingMail:0,failedMail:0,activeSessions:3,databaseBytes:12582912}];
    else if(url.pathname==='/api/leads')body=[{leadId:1,leadNumber:'ECC-2026-0001',fullName:'Maya Chen',email:'maya@example.com',phone:'+63 917 555 1200',source:'Website',consultantId:1,consultantName:'Alex Rivera',quality:'Hot',stage:'Qualified',destination:'Canada',service:'Student Visa',notes:null,lastContact:'2026-10-16',nextFollowup:'2026-10-18',createdAt:'2026-10-01T00:00:00Z',updatedAt:'2026-10-16T00:00:00Z'}];
    else if(url.pathname==='/api/clients')body=[{id:4,number:'ECC-4',fullName:'Maya Chen with a long family name',email:'maya.with.a.long.email.address@example.com',phone:'+63 917 555 1200',caseOfficerId:1,caseOfficerName:'Alex Rivera',createdAt:'2026-10-01T00:00:00Z',revision:2}];
    else if(url.pathname==='/api/clients/4')body={client:{id:4,number:'ECC-4',fullName:'Maya Chen',email:'maya@example.com',phone:null,caseOfficerId:1,caseOfficerName:'Alex Rivera',createdAt:'2026-10-01T00:00:00Z',revision:2},cases:[{id:9,clientId:4,category:'Student Visa',destination:'Canada',stage:'Submitted',deadline:null,createdAt:'2026-10-01T00:00:00Z',revision:1}],documents:[],tasks:[],activities:[]};
    else if(url.pathname.startsWith('/api/workspace/')){
      const section=url.pathname.split('/')[3]==='record'?url.pathname.split('/')[6]:url.pathname.split('/')[3];
      const rows={
        tasks:[{id:7,title:'Review passport',description:'Keep this description',owner:'client:4',recordName:'Maya Chen',assignee:1,assigneeName:'Alex Rivera',dueDate:'2030-01-01',priority:'High',status:'Pending',revision:3}],
        documents:[{id:9,title:'Passport checklist',owner:'client:4',status:'Received',required:'true',revision:5,versions:[{documentId:12,version:1,filename:'passport.pdf',scanStatus:'Clean'}]}],
        security:[{id:'session-prefix',title:'Browser/API session',created:'2026-10-18',expires:'2026-10-19'}]
      };
      body={rows:rows[section]||[],options:[{value:'staff:1',label:'Alex Rivera'},{value:'client:4',label:'Maya Chen'},{value:'document:12',label:'passport.pdf'}],security:{enabled:false,users:[]}};
      if(section==='conflict')body={id:7,title:'Changed by colleague',description:'Keep this description',priority:'High',status:'Pending',assignee:1,dueDate:'2030-01-01',revision:4};
      if(req.method==='POST'){
        this.lastFeatureBody=JSON.parse(req.postData||'{}');
        if(section==='tasks'){status=409;body={error:'Someone else changed this record. Reload it before saving.'};}
        else body={message:'Saved successfully'};
      }
    }
    else if(url.pathname.startsWith('/api/'))body=[];
    else{
      let file=url.pathname==='/'||!path.extname(url.pathname)?'index.html':url.pathname.slice(1);
      const target=path.join(root,'web/dist',file);mime=file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html';
      body=fs.readFileSync(target);
    }
    if(url.pathname==='/api/leads' && url.searchParams.get('q')) {
      const query=url.searchParams.get('q');
      body=body.map(record=>({...record,fullName:query==='slow'?'Stale result':'Current result'}));
      if(query==='slow')await delay(1200);
    }
    if(url.pathname==='/api/archive') {
      const offset=Number(url.searchParams.get('offset')||0);
      body=Array.from({length:offset===0?50:3},(_,i)=>({id:offset+i+4,kind:'lead',name:offset===0?'Archived contact':'Later archived contact',number:'ECC-2026-'+(offset+i),date:'2026-10-16'}));
    }
    if(!Buffer.isBuffer(body))body=Buffer.from(JSON.stringify(body));
    await this.send('Fetch.fulfillRequest',{requestId:msg.params.requestId,responseCode:status,responseHeaders:[{name:'Content-Type',value:mime}],body:body.toString('base64')});
  }
  async start(){await this.send('Browser.getVersion',{},null);const {targetId}=await this.send('Target.createTarget',{url:'about:blank'},null);const {sessionId}=await this.send('Target.attachToTarget',{targetId,flatten:true},null);this.session=sessionId;await this.send('Runtime.enable');await this.send('Page.enable');await this.send('Fetch.enable',{patterns:[{urlPattern:'*'}]});await this.send('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});await this.send('Page.navigate',{url:'http://ecc.test/'});}
  async evaluate(expression){const r=await this.send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
  async wait(expression){for(let i=0;i<100;i++){if(await this.evaluate(expression))return;await delay(50);}throw Error('Not found: '+expression+'\n'+await this.evaluate('document.body.innerText'));}
  async clickText(text){await this.evaluate(`Array.from(document.querySelectorAll('button,a')).find(x=>x.textContent.trim()===${JSON.stringify(text)}).click()`);}
  async screenshot(name){const result=await this.send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(os.tmpdir(),name),Buffer.from(result.data,'base64'));}
  async close(){for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Browser closed'));}this.pending.clear();this.child.kill('SIGTERM');await delay(200);fs.rmSync(this.dir,{recursive:true,force:true,maxRetries:3});}
}


test('phone layouts keep navigation and records accessible', {timeout:60000}, async()=>{
 const b=new Browser();
 try {
  await b.start();
  await b.wait(`document.querySelector('input[type="email"]')`);
  await b.evaluate(`for (const [type,value] of [['email','alex@example.com'],['password','test-password-123']]) { const el=document.querySelector('input[type="'+type+'"]'); el.value=value; el.dispatchEvent(new Event('input',{bubbles:true})); }`);
  await b.clickText('Sign in →');
  await b.wait(`document.querySelector('.dashboard-stats')`);
  for (const width of [320,390,720]) {
   await b.send('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:true});
   await b.evaluate(`document.fonts.ready`);
   assert(await b.evaluate(`document.documentElement.scrollWidth <= innerWidth`),'dashboard must fit '+width);
   assert(await b.evaluate(`document.querySelector('.header').getBoundingClientRect().height < 180`),'compact phone header');
   assert(await b.evaluate(`getComputedStyle(document.querySelector('.mobile-bottom-nav')).display==='grid'`),'bottom navigation is visible');
   assert(await b.evaluate(`Array.from(document.querySelectorAll('.mobile-bottom-nav > a,.mobile-more > summary')).every(el=>el.getBoundingClientRect().height>=44)`),'navigation has touch targets');
   await b.screenshot('ecc-pwa-dashboard-'+width+'.png');
  }
  await b.clickText('Leads'); await b.wait(`document.querySelector('.leads-table')`);
  await b.send('Emulation.setDeviceMetricsOverride',{width:320,height:844,deviceScaleFactor:1,mobile:true});
  assert(await b.evaluate(`document.documentElement.scrollWidth <= innerWidth`),'lead page must fit phone');
  assert(await b.evaluate(`getComputedStyle(document.querySelector('.leads-table td:nth-child(6)')).display !== 'none'`),'columns remain accessible');
  await b.evaluate(`document.querySelector('.mobile-more summary').click()`);
  assert(await b.evaluate(`const r=document.querySelector('.mobile-menu-panel').getBoundingClientRect(); r.left>=0 && r.right<=innerWidth && r.bottom<=document.querySelector('.mobile-bottom-nav').getBoundingClientRect().top`),'more menu fits above navigation');
  await b.evaluate(`document.querySelector('.mobile-more summary').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))`);
  assert(await b.evaluate(`!document.querySelector('.mobile-more').open`),'Escape dismisses tools');
  await b.evaluate(`document.querySelector('.mobile-bottom-nav a[href="/clients"]').click()`);
  await b.wait(`document.querySelector('.clients-table tbody tr')`);
  for (const width of [320,390,720]) {
   await b.send('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:true});
   assert(await b.evaluate(`document.documentElement.scrollWidth<=innerWidth`),'client cards fit '+width);
   assert(await b.evaluate(`getComputedStyle(document.querySelector('.clients-table tbody tr')).display==='grid'`),'clients use mobile cards');
   assert.equal(await b.evaluate(`document.querySelectorAll('.clients-table td[data-label]').length`),4,'all client metadata retained');
   await b.screenshot('ecc-mobile-clients-'+width+'.png');
  }
  await b.evaluate(`document.querySelector('.clients-table a').click()`);
  await b.wait(`document.querySelector('.client-applications-table')`);
  assert(await b.evaluate(`getComputedStyle(document.querySelector('.client-applications-table tbody tr')).display==='grid'`),'applications use mobile cards');
  await b.clickText('Edit');
  await b.wait(`document.querySelector('.modal-content')`);
  assert(await b.evaluate(`getComputedStyle(document.querySelector('.mobile-bottom-nav')).visibility==='hidden'`),'dialog has priority over bottom navigation');
  assert(await b.evaluate(`const r=document.querySelector('.modal-content').getBoundingClientRect();r.left>=0&&r.right<=innerWidth&&r.bottom<=innerHeight`),'dialog fits the phone');
  await b.screenshot('ecc-mobile-client-edit.png');
  await b.clickText('Cancel');
  await b.evaluate(`document.querySelector('.mobile-more summary').click()`);
  await b.evaluate(`document.querySelector('.mobile-menu-link[href="/work/search"]').click()`);
  await b.wait(`location.pathname==='/work/search'`);
  assert(await b.evaluate(`!document.querySelector('.mobile-more').open`),'selecting a tool dismisses menu');
  await b.send('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
  assert(await b.evaluate(`getComputedStyle(document.querySelector('.mobile-bottom-nav')).display==='none'`),'desktop uses sidebar navigation');
  assert.deepEqual(b.errors,[]);
 } finally {await b.close();}
});
