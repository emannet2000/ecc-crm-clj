const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process');
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
  async event(msg){if(msg.method==='Runtime.exceptionThrown')this.errors.push(msg.params.exceptionDetails.text);}
  async start(url){await this.send('Browser.getVersion',{},null);const {targetId}=await this.send('Target.createTarget',{url:'about:blank'},null);const {sessionId}=await this.send('Target.attachToTarget',{targetId,flatten:true},null);this.session=sessionId;await this.send('Runtime.enable');await this.send('Page.enable');await this.send('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});await this.send('Page.navigate',{url});}
  async evaluate(expression){const r=await this.send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
  async wait(expression){for(let i=0;i<100;i++){if(await this.evaluate(expression))return;await delay(50);}throw Error('Not found: '+expression+'\n'+await this.evaluate('document.body.innerText'));}
  async clickText(text){await this.evaluate(`Array.from(document.querySelectorAll('button,a')).find(x=>x.textContent.trim()===${JSON.stringify(text)}).click()`);}
  async screenshot(name){const result=await this.send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(os.tmpdir(),name),Buffer.from(result.data,'base64'));}
  async close(){for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Browser closed'));}this.pending.clear();this.child.kill('SIGTERM');await delay(200);fs.rmSync(this.dir,{recursive:true,force:true,maxRetries:3});}
}
module.exports={Browser,delay};
