const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),net=require('node:net');
const {spawn,execFileSync}=require('node:child_process');
const {Browser,delay}=require('./live-browser-driver.cjs');
const root=path.resolve(__dirname,'..');
const binary=process.env.ECC_API_BIN;

async function freePort(){const s=net.createServer();await new Promise((ok,bad)=>{s.once('error',bad);s.listen(0,'127.0.0.1',ok);});const port=s.address().port;await new Promise(ok=>s.close(ok));return port;}

test('live financial workflows, permissions and mobile layout',{timeout:180000},async()=>{
 assert(binary,'Set ECC_API_BIN to the compiled API executable');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-live-finance-'));
 let port;try{port=await freePort();}catch(error){fs.rmSync(dir,{recursive:true,force:true});throw error;}
 const base='http://127.0.0.1:'+port;
 const env={...process.env,APP_ENV:'development',DATABASE_PATH:path.join(dir,'test.sqlite3'),JWT_SECRET:'isolated-browser-test-secret-123456789',SEED_DEMO:'false',PUBLIC_URL:base,PORT:String(port),WEB_DIST:path.join(root,'web/dist'),ASSIGNED_ONLY:'false',REQUIRE_ADMIN_MFA:'false'};
 const adminPassword='browser-admin-password-123';
 execFileSync(binary,['adduser','admin@browser.test','Browser Admin','admin',adminPassword],{cwd:root,env,stdio:'pipe'});
 const server=spawn(binary,[],{cwd:root,env,stdio:['ignore','pipe','pipe']});
 let log='';server.stdout.on('data',d=>{log=(log+d).slice(-8000);});server.stderr.on('data',d=>{log=(log+d).slice(-8000);});
 const b=new Browser();
 try{
  let ready=false;for(let i=0;i<100;i++){try{if((await fetch(base+'/api/ready')).ok){ready=true;break;}}catch{}await delay(100);}
  assert(ready,'API did not start: '+log);
  async function api(route,method='GET',body,token){const r=await fetch(base+route,{method,headers:{...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined});const data=await r.json();assert(r.ok,method+' '+route+' '+r.status+' '+JSON.stringify(data));return data;}
  const signed=await api('/api/auth/login','POST',{lrEmail:'admin@browser.test',lrPassword:adminPassword});
  const token=signed.token;
  const staff=await api('/api/users','POST',{nuName:'Finance Viewer',nuEmail:'staff@browser.test',nuRole:'consultant',nuPassword:'browser-staff-password-123'},token);
  const access={user:staff.id,expectedRevision:0,password:adminPassword,accessLevel:'assigned',edit:'denied',delete:'denied',download:'denied',export:'denied',email:'denied',portal:'denied',sales_view:'allowed',finance_view:'allowed',payments_record:'denied',expenses_record:'denied',expenses_approve:'denied',finance_periods:'denied',finance_reconcile:'denied'};
  await api('/api/workspace/security/access','POST',access,token);
  const client=await api('/api/clients','POST',{ncFullName:'Live finance client',ncEmail:'client@browser.test',ncPhone:null,ncCaseOfficer:staff.id},token);
  const invoice={owner:'client:'+client.id,description:'Browser service',currency:'PHP',amount:'100.00',dueDate:'2020-01-01',status:'Draft'};
  await api('/api/workspace/invoices/save','POST',invoice,token);
  await api('/api/workspace/invoices/save','POST',{...invoice,id:1,status:'Issued',expectedRevision:1},token);
  async function fill(values){for(const [key,value] of Object.entries(values))await b.evaluate(`const f=document.querySelector(${JSON.stringify(key.startsWith('#')?key:'#work-'+key)});if(!f)throw Error('Missing field');f.value=${JSON.stringify(value)};f.dispatchEvent(new Event('input',{bubbles:true}));`);}
  async function navigate(route,wait){await b.send('Page.navigate',{url:base+route});await b.wait(wait);}
  async function confirm(text){await b.clickText(text);await b.wait(`document.body.innerText.includes('Confirm this action')`);await b.clickText('Confirm');await b.wait(`document.body.innerText.includes('Financial entry saved') && !Array.from(document.querySelectorAll('button')).some(x=>x.textContent.includes('Working'))`);}
  async function login(email,password){await b.wait(`document.querySelector('input[type="email"]')`);await b.evaluate(`for(const [selector,value] of ${JSON.stringify([['input[type="email"]',email],['input[type="password"]',password]])}){const f=document.querySelector(selector);f.value=value;f.dispatchEvent(new Event('input',{bubbles:true}));}`);await b.clickText('Sign in →');await b.wait(`document.querySelector('.header')`);}
  await b.start(base+'/');await login('admin@browser.test',adminPassword);
  await navigate('/work/payments',`document.body.innerText.includes('Live finance client') && Array.from(document.querySelectorAll('button')).some(x=>x.textContent==='Record payment')`);
  await b.clickText('Select / edit');await fill({amount:'40.00',paidOn:'2020-01-10',method:'Bank transfer',reference:'LIVE-BANK-1'});await confirm('Record payment');
  let balances=await api('/api/workspace/balances','GET',undefined,token);assert.equal(balances.rows[0].balance,'60.00');
  await navigate('/work/payment-history?invoice=1',`document.body.innerText.includes('Receipt 1')`);
  await b.clickText('Select / edit');await fill({paidOn:'2020-01-11',reason:'Correct browser receipt'});await confirm('Reverse selected receipt');
  balances=await api('/api/workspace/balances','GET',undefined,token);assert.equal(balances.rows[0].balance,'100.00');
  await navigate('/work/expenses',`Array.from(document.querySelectorAll('button')).some(x=>x.textContent==='Submit expense')`);
  await fill({supplier:'Live supplier',description:'Browser expense',category:'Office',amount:'25.00',expenseOn:'2020-02-01'});await confirm('Submit expense');
  await b.wait(`document.body.innerText.includes('Live supplier')`);await b.clickText('Select / edit');await confirm('Approve expense');
  await b.wait(`document.body.innerText.includes('Approved')`);await b.clickText('Select / edit');await fill({paidOn:'2020-02-02',method:'Cash',paymentReference:'LIVE-EXP-1'});await confirm('Record expense payment');
  await b.wait(`document.body.innerText.includes('Paid')`);await b.clickText('Select / edit');await fill({paidOn:'2020-02-03',reason:'Correct browser expense'});await confirm('Reverse expense payment');
  const expenses=await api('/api/workspace/expenses','GET',undefined,token);assert.equal(expenses.rows[0].status,'Reversed');
  for(const route of ['/work/payments','/work/payment-history','/work/expenses','/work/sales']){
   await b.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
   await navigate(route,`location.pathname===${JSON.stringify(route)} && document.body.innerText.includes(${JSON.stringify(route==='/work/expenses'?'Live supplier':route==='/work/sales'?'Amounts by currency':'Live finance client')})`);
   assert(await b.evaluate(`document.documentElement.scrollWidth<=window.innerWidth`),'Horizontal overflow on '+route);
   await b.screenshot('ecc-live-finance-'+route.split('/').pop()+'-mobile.png');
  }
  await b.send('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
  await b.clickText('Log out');await login('staff@browser.test','browser-staff-password-123');
  await navigate('/work/payments',`document.body.innerText.includes('Live finance client')`);
  assert.equal(await b.evaluate(`Array.from(document.querySelectorAll('button')).some(x=>x.textContent==='Record payment')`),false,'Payment writer control is hidden');
  const rejected=await b.evaluate(`fetch('/api/workspace/payments/record',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:1,amount:'1.00',paidOn:'2020-01-01',method:'Cash',expectedRevision:4})}).then(r=>r.status)`);
  assert.equal(rejected,403,'Direct API call cannot bypass financial privilege');
  assert.deepEqual(b.errors,[]);
 }finally{await b.close();server.kill('SIGTERM');await delay(300);fs.rmSync(dir,{recursive:true,force:true,maxRetries:3});}
});
