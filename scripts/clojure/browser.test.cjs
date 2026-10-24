const {test}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const fs=require('node:fs');
const http=require('node:http');
const {Browser}=require('../../api/test/live-browser-driver.cjs');

test('compiled re-frame app signs in, creates a lead, and rejects stale search results', {timeout:90000}, async()=>{
  let signedIn=false,leads=[];
  const requests=[];
  const server=http.createServer(async(req,res)=>{
    const url=new URL(req.url,'http://localhost');
    if(!url.pathname.startsWith('/api/')){
      const file=path.resolve(__dirname,'../../frontend/public','.'+url.pathname.replace(/\/$/,'/index.html'));
      if(!file.startsWith(path.resolve(__dirname,'../../frontend/public')+path.sep)){res.writeHead(403);res.end();return;}
      try{res.setHeader('content-type',file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(file));}catch{res.writeHead(404);res.end();}return;
    }
    requests.push(url.pathname);
    let body={};
    if(req.method==='POST'){let raw='';for await (const chunk of req)raw+=chunk;body=JSON.parse(raw||'{}');}
    res.setHeader('content-type','application/json');
    if(url.pathname==='/api/auth/me'){res.statusCode=signedIn?200:401;res.end(JSON.stringify(signedIn?{id:1,name:'Admin',role:'admin'}:{error:'Sign in'}));return;}
    if(url.pathname==='/api/auth/login'){signedIn=true;res.end(JSON.stringify({user:{id:1,name:'Admin',role:'admin'}}));return;}
    if(url.pathname==='/api/auth/logout'){signedIn=false;res.end('{}');return;}
    if(url.pathname==='/api/stats'){res.end(JSON.stringify({totalLeads:leads.length,totalClients:0,openTasks:0,byStage:[]}));return;}
    if(url.pathname==='/api/leads'){
      if(req.method==='POST'){leads.push({...body,id:1,revision:1});res.end(JSON.stringify(leads[0]));return;}
      const q=url.searchParams.get('q');
      const result=q?[{id:1,fullName:q==='slow'?'Stale result':'Current result',stage:'New Lead'}]:leads;
      if(q==='slow')await new Promise(r=>setTimeout(r,1000));
      res.end(JSON.stringify({rows:result,total:result.length}));return;
    }
    res.end(JSON.stringify({rows:[],options:[]}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const browser=new Browser();
  const fill=async(name,value)=>{
    await browser.evaluate(`(()=>{const e=document.querySelector('[name="${name}"]');e.focus();e.select();})()`);
    await browser.send('Input.insertText',{text:value});
    await browser.evaluate('new Promise(resolve=>setTimeout(resolve,80))');
  };
  try{
    await browser.start(`http://127.0.0.1:${server.address().port}/`);
    await browser.wait('!!document.querySelector("input[name=email]")');
    await fill('email','admin@example.com');await fill('password','a-long-password');
    await browser.clickText('Sign in');
    await browser.wait('document.body.innerText.includes("Overview") && document.body.innerText.includes("Sign out")');
    await browser.clickText('Leads');await browser.wait('document.body.innerText.includes("No records yet")');
    await browser.clickText('+ New record');await fill('fullName','Clojure Student');await fill('email','student@example.com');
    await browser.evaluate('new Promise(resolve=>setTimeout(resolve,150))');
    await browser.clickText('Save');await browser.wait('document.querySelector("table")?.innerText.includes("Clojure Student")');
    assert.equal(leads[0].fullName,'Clojure Student');
    await browser.screenshot('ecc-clojure-desktop.png');
    await browser.evaluate(`(()=>{const e=document.querySelector('input[type=search]');Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,'slow');e.dispatchEvent(new Event('input',{bubbles:true}));})()`);
    await new Promise(r=>setTimeout(r,50));
    await browser.evaluate(`(()=>{const e=document.querySelector('input[type=search]');Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,'fast');e.dispatchEvent(new Event('input',{bubbles:true}));})()`);
    await browser.wait('document.querySelector("table")?.innerText.includes("Current result")');
    await new Promise(r=>setTimeout(r,1200));
    assert.ok(!(await browser.evaluate('document.body.innerText')).includes('Stale result'));
    await browser.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await browser.screenshot('ecc-clojure-mobile.png');
    assert.equal(await browser.evaluate('document.documentElement.scrollWidth <= innerWidth'),true);
    await browser.clickText('Sign out');await browser.wait('!!document.querySelector("input[name=password]")');
    assert.deepEqual(browser.errors,[]);
    assert.ok(requests.includes('/api/auth/logout'));
  }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
});
