const {test}=require('node:test');
const assert=require('node:assert/strict');
const http=require('node:http');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {Browser,delay}=require('./live-browser-driver.cjs');

for(const [name,executable,expected] of [
 ['missing executable','/ecc-missing-chromium-executable',/ENOENT/],
 ['early browser exit','/bin/false',/Chromium exited 1|ECONNRESET|EPIPE/]
])test('browser startup reports '+name+' promptly',{timeout:5000},async()=>{
 const previous=process.env.CHROME_PATH;
 process.env.CHROME_PATH=executable;
 const browser=new Browser();
 try{await delay(100);await assert.rejects(browser.send('Browser.getVersion'),expected);}
 finally{await browser.close();if(previous===undefined)delete process.env.CHROME_PATH;else process.env.CHROME_PATH=previous;}
});

test('launcher permission errors survive delayed finance setup',{timeout:5000},async()=>{
 const previous=process.env.CHROME_PATH;
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-launcher-test-'));
 const executable=path.join(dir,'chromium.sh');
 fs.writeFileSync(executable,'#!/bin/sh\nexit 0\n',{mode:0o600});
 process.env.CHROME_PATH=executable;
 const browser=new Browser();
 try{await delay(100);await assert.rejects(browser.send('Browser.getVersion'),/EACCES/);}
 finally{await browser.close();fs.rmSync(dir,{recursive:true,force:true});if(previous===undefined)delete process.env.CHROME_PATH;else process.env.CHROME_PATH=previous;}
});

test('multiprocess browser loads a login field over real HTTP',{
 skip:!process.env.CHROME_PATH,timeout:20000
},async()=>{
 const previous=process.env.CHROME_SINGLE_PROCESS;
 delete process.env.CHROME_SINGLE_PROCESS;
 const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end('<input type="email" aria-label="Email">');});
 let browser;
 try{
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  browser=new Browser();
  await browser.start('http://127.0.0.1:'+server.address().port+'/');
  await browser.wait('document.querySelector(\'input[type="email"]\')');
  assert.deepEqual(browser.errors,[]);
  assert(!browser.stderr.includes('FD ownership violation'),browser.stderr);
 }finally{
  if(browser)await browser.close();
  await new Promise(resolve=>server.close(resolve));
  if(previous===undefined)delete process.env.CHROME_SINGLE_PROCESS;else process.env.CHROME_SINGLE_PROCESS=previous;
 }
});
