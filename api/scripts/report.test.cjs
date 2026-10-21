const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const vm=require('node:vm');
const {execFileSync}=require('node:child_process');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-reports-'));
try {
 const output=process.env.ECC_ELM_REPORT_JS||path.join(dir,'main.js');
 if (!process.env.ECC_ELM_REPORT_JS) execFileSync(process.env.ELM_BIN||'/usr/bin/elm',['make','src/Main.elm','--output='+output],{cwd:path.join(__dirname,'../web'),stdio:'pipe'});
 const expose=`scope.reportTests={A2,A3,list:_List_fromArray,initial:$author$project$State$initialModel,url:$elm$url$Url$fromString,json:_Json_wrap,unwrap:_Json_unwrap,payload:$author$project$Reports$payload,update:$author$project$Main$update,setting:$author$project$State$ReportSetting,featureField:$author$project$State$FeatureField,run:$author$project$State$FeatureRun};`;
 const context={console:{log(){},warn(){}}};
 vm.runInNewContext(fs.readFileSync(output,'utf8').replace('_Platform_export({',expose+'_Platform_export({'),context);
 const e=context.reportTests;
 const initial=()=>({...e.A2(e.initial,{},e.url('http://ecc.test/work/reports').a),opsData:e.list([
  e.json({title:'Alex',leads:12,converted:2,openTasks:9}),
  e.json({title:'Maya',leads:3,converted:1,openTasks:100}),
  e.json({title:'Dana',leads:25,converted:4,openTasks:20})
 ])});
 const set=(m,k,v)=>e.A2(e.update,e.A2(e.setting,k,v),m).a;
 const payload=m=>JSON.parse(JSON.stringify(e.unwrap(e.A3(e.payload,m,'reports','preview'))));
 test('numeric sorting, filtering and hidden columns match exported payload',()=>{
  let m=initial();m=set(m,'sort','openTasks');m=set(m,'direction','descending');
  let p=payload(m);assert.deepEqual(p.rows.map(x=>x[0]),['Maya','Dana','Alex']);
  m=set(m,'metric','leads');m=set(m,'minimum','10');m=set(m,'reports:hide:converted','true');
  p=payload(m);assert.deepEqual(p.rows.map(x=>x[0]),['Dana','Alex']);assert(!p.headers.includes('Converted leads'));
  m=set(m,'filter','aLeX');assert.deepEqual(payload(m).rows.map(x=>x[0]),['Alex']);
  assert.equal(m.formDirty,false,'layout settings are not unsaved CRM edits');
 });
 test('date ranges reject one-sided dates and clear to default cleanly',()=>{
  let m=initial();m=e.A2(e.update,e.A2(e.featureField,'from','2026-01-01'),m).a;
  let invalid=e.A2(e.update,e.run('range'),m).a;assert(invalid.featureError.includes('both dates'));
  m=e.A2(e.update,e.A2(e.featureField,'from',''),m).a;
  const clear=e.A2(e.update,e.run('range'),m).a;assert.equal(clear.featureSearch,'');
 });
 test('print metadata uses the active fetched date range',()=>{
  let m={...initial(),featureSearch:'2026-01-01,2026-01-31'};
  m=set(m,'title','Quarter review');m=set(m,'orientation','landscape');
  const p=payload(m);assert.equal(p.title,'Quarter review');assert.equal(p.range,'2026-01-01 to 2026-01-31');assert.equal(p.orientation,'landscape');
 });
} finally {fs.rmSync(dir,{recursive:true,force:true});}
