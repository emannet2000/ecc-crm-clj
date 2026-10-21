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
    if(url.pathname==='/api/auth/me'){status=this.signedIn?200:401;body=this.signedIn?user:{error:'Not authenticated'};}
    else if(url.pathname==='/api/auth/login'){this.signedIn=true;body={token:'memory-only',user};}
    else if(url.pathname==='/api/auth/logout'){this.signedIn=false;body={loggedOut:true};}
    else if(url.pathname==='/api/auth/recover')body={message:'queued'};
    else if(url.pathname==='/api/stats')body={stTotalLeads:128,stHotLeads:24,stTotalClients:42,stOpenTasks:16,stOverdueTasks:3,stStageCounts:[{scStage:'New Lead',scCount:45},{scStage:'Qualified',scCount:32},{scStage:'Proposal Sent',scCount:12}],stSourceCounts:[{srcSource:'Website',srcCount:48}],stUpcomingTasks:[],stRecentActivity:[]};
    else if(url.pathname==='/api/users')body=[user];
    else if(url.pathname==='/api/reminders')body=[{id:9,kind:'followup',title:'Follow up: Maya Chen',due:'2026-10-18',path:'/leads/1',read:false}];
    else if(url.pathname.endsWith('/read'))body={read:true};
    else if(url.pathname==='/api/archive')body=[{id:4,kind:'lead',name:'Archived contact',number:'L-2026-0004',date:'2026-10-16'}];
    else if(url.pathname==='/api/duplicates')body=[{field:'email',value:'maya@example.com',records:[{id:1,kind:'lead',name:'Maya Chen'},{id:2,kind:'client',name:'Maya Chen'}]}];
    else if(url.pathname==='/api/metrics')body=[{pendingMail:0,failedMail:0,activeSessions:3,databaseBytes:12582912}];
    else if(url.pathname==='/api/leads')body=[{leadId:1,leadNumber:'L-2026-0001',fullName:'Maya Chen',email:'maya@example.com',phone:'+63 917 555 1200',source:'Website',consultantId:1,consultantName:'Alex Rivera',quality:'Hot',stage:'Qualified',destination:'Canada',service:'Student Visa',notes:null,lastContact:'2026-10-16',nextFollowup:'2026-10-18',createdAt:'2026-10-01T00:00:00Z',updatedAt:'2026-10-16T00:00:00Z'}];
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
      body=Array.from({length:offset===0?50:3},(_,i)=>({id:offset+i+4,kind:'lead',name:offset===0?'Archived contact':'Later archived contact',number:'L-2026-'+(offset+i),date:'2026-10-16'}));
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

test('workspace UI: authentication, navigation, responsive layout and operations', {timeout:90000},async t=>{
  const b=new Browser();
  try{
    await b.start();
    await t.test('login and password recovery are accessible',async()=>{
      await b.wait(`document.body.innerText.includes('Good to see you.')`);
      assert.equal(await b.evaluate(`document.querySelector('input[type="email"]').labels.length`),1);
      assert.equal(await b.evaluate(`localStorage.getItem('ecc-token')`),null);
      await b.screenshot('ecc-login-desktop.png');
      await b.clickText('Forgot your password?');
      await b.wait(`document.body.innerText.includes('Let’s get you back in.')`);
      await b.evaluate(`document.querySelector('input[type="email"]').value='alex@example.com';document.querySelector('input[type="email"]').dispatchEvent(new Event('input',{bubbles:true}));`);
      await b.clickText('Send recovery link →');
      await b.wait(`document.body.innerText.includes('If your account exists')`);
      await b.clickText('← Back to sign in');
    });
    await t.test('sign-in uses the deployed origin and opens the dashboard',async()=>{
      await b.evaluate(`const pw=document.querySelector('input[type="password"]');pw.value='test-password-123';pw.dispatchEvent(new Event('input',{bubbles:true}));`);
      await b.clickText('Sign in →');
      await b.wait(`document.body.innerText.includes('A clear view of what’s next.') && document.body.innerText.includes('128')`);
      assert(b.requests.includes('/api/auth/login'));
      assert.equal(await b.evaluate(`document.querySelectorAll('.dashboard-stats .stat').length`),4);
      assert.equal(await b.evaluate(`document.querySelectorAll('.nav-group').length`),3);
      assert.equal(await b.evaluate(`document.querySelector('.nav-link.active').getAttribute('aria-current')`),'page');
      assert.equal(await b.evaluate(`document.querySelector('.nav-link svg').namespaceURI`),'http://www.w3.org/2000/svg');
      assert(await b.evaluate(`document.querySelector('.attention-strip').innerText.includes('3 tasks')`));
      assert.equal(await b.evaluate(`localStorage.getItem('ecc-token')`),null);
      await b.screenshot('ecc-dashboard-desktop.png');
    });
    await t.test('lead list and pagination render',async()=>{
      await b.clickText('Leads');await b.wait(`document.querySelector('.data-table') && document.body.innerText.includes('Maya Chen')`);
      assert(await b.evaluate(`document.body.innerText.includes('page 1')`));
      assert.equal(await b.evaluate(`document.querySelector('.contact-identity').getAttribute('href')`),'/leads/1');
      assert.equal(await b.evaluate(`document.querySelector('.search-input').getAttribute('aria-label')`),'Search leads');
      await b.screenshot('ecc-leads-desktop.png');
    });
    await t.test('late search responses cannot replace the current query',async()=>{
      const input=value=>b.evaluate(`const input=document.querySelector('.search-input');input.value=${JSON.stringify(value)};input.dispatchEvent(new Event('input',{bubbles:true}));`);
      await input('slow');
      for(let i=0;i<100&&!b.requests.some(path=>path.includes('q=slow'));i++)await delay(20);
      assert(b.requests.some(path=>path.includes('q=slow')));
      await input('fast');
      await b.wait(`document.body.innerText.includes('Current result')`);
      await delay(1300);
      assert.equal(await b.evaluate(`document.body.innerText.includes('Stale result')`),false);
      assert(await b.evaluate(`document.body.innerText.includes('Current result')`));
      await input('');
      await b.wait(`document.body.innerText.includes('Maya Chen')`);
    });
    await t.test('archive supports records beyond the first page',async()=>{
      await b.clickText('Archive');await b.wait(`document.body.innerText.includes('Archived contact')`);
      await b.clickText('Next →');await b.wait(`document.body.innerText.includes('Later archived contact')`);
      assert(await b.evaluate(`document.body.innerText.includes('page 2')`));
      await b.clickText('← Previous');await b.wait(`document.body.innerText.includes('Archived contact')`);
    });
    await t.test('task board has three clearly labeled workflow columns',async()=>{
      await b.clickText('Tasks');
      await b.wait(`document.querySelectorAll('.task-board .task-column').length === 3`);
      assert.deepEqual(await b.evaluate(`Array.from(document.querySelectorAll('.task-column h3')).map(x=>x.textContent.trim())`),['Pending','In Progress','Done']);
    });
    await t.test('reminders, duplicates, archive and system pages render',async()=>{
      for(const [nav,content] of [['Reminders','Follow up: Maya Chen'],['Duplicates','maya@example.com'],['Archive','Archived contact'],['System','Active sessions']]){
        await b.clickText(nav);await b.wait(`document.body.innerText.includes(${JSON.stringify(content)})`);
      }
    });
    await t.test('workflow editing preserves versions and stale forms',async()=>{
      await b.clickText('Edit and assign tasks');
      await b.wait(`document.body.innerText.includes('Review passport')`);
      await b.clickText('Select / edit');
      assert.equal(await b.evaluate(`document.querySelector('#work-title').value`),'Review passport');
      await b.clickText('Save selected task');
      await b.wait(`document.body.innerText.includes('Review changes before saving')`);
      assert(await b.evaluate(`document.body.innerText.includes('Changed by colleague')`));
      await b.clickText('Keep reviewing later');
      assert.equal(b.lastFeatureBody.expectedRevision,'3');
      assert.equal(await b.evaluate(`document.querySelector('#work-title').value`),'Review passport');
      await b.clickText('Document checklists');
      await b.wait(`document.body.innerText.includes('Passport checklist')`);
      await b.clickText('Select / edit');
      assert.equal(await b.evaluate(`document.querySelector('#work-title').value`),'Passport checklist');
      assert.equal(await b.evaluate(`document.querySelector('#work-owner').value`),'client:4');
      assert.equal(await b.evaluate(`document.querySelector('a[href="/api/documents/12/download"]').textContent`),'Version 1 · passport.pdf');
      await b.clickText('Account security');
      await b.wait(`document.body.innerText.includes('Start authenticator setup')`);
      assert.equal(await b.evaluate(`document.querySelector('#work-password').type`),'password');
      await b.clickText('Merge duplicates');
      await b.wait(`document.body.innerText.includes('Preview merge')`);
      assert.equal(await b.evaluate(`document.querySelector('#work-entity').value`),'leads');
    });
    await t.test('client pages expose scoped work and document upload controls',async()=>{
      await b.evaluate(`const a=document.createElement('a');a.href='/clients/4';a.textContent='Open fixture client';document.body.append(a);a.click();`);
      await b.wait(`document.body.innerText.includes('Work on this client or case')`);
      await b.clickText('Document checklist');
      await b.wait(`document.querySelector('#checklist-file')`);
      assert.equal(await b.evaluate(`document.querySelector('#checklist-file').labels.length`),1);
      assert(await b.evaluate(`document.body.innerText.includes('Review queue')`));
      await b.evaluate(`const s=document.querySelector('#case-work-scope');s.value='case:9';s.dispatchEvent(new Event('input',{bubbles:true}));`);
      await b.wait(`document.querySelector('#case-work-scope').value==='case:9'`);
      assert(b.requests.some(path=>path.startsWith('/api/workspace/record/case/9/documents')));
    });
    await t.test('mobile navigation and content fit the viewport',async()=>{
      await b.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
      await b.clickText('Dashboard');await b.wait(`document.body.innerText.includes('128')`);
      assert(await b.evaluate(`document.documentElement.scrollWidth <= window.innerWidth`));
      await b.screenshot('ecc-dashboard-mobile.png');
    });
    await t.test('logout clears the workspace and returns to sign in',async()=>{
      await b.clickText('Log out');await b.wait(`document.body.innerText.includes('Good to see you.')`);
      assert.equal(await b.evaluate(`document.querySelector('.header')`),null);
    });
    assert.deepEqual(b.errors,[]);
  } finally {await b.close();}
});
