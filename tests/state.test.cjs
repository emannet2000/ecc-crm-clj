const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const vm=require('node:vm');
const {execFileSync}=require('node:child_process');

// Execute the real compiled Elm update function without a browser or HTTP fixtures.
const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-state-'));
const output=process.env.ECC_ELM_STATE_JS||path.join(directory,'main.js');
try {
  if(!process.env.ECC_ELM_STATE_JS)execFileSync(process.env.ELM_BIN||'elm',['make','src/Main.elm','--output='+output],{
    cwd:path.resolve(__dirname,'../web'),env:{...process.env,GHCRTS:'-N2'},stdio:'pipe'
  });
  const expose=`scope.stateTests={A2,A3,list:_List_fromArray,initial:$author$project$State$initialModel,
    url:$elm$url$Url$fromString,update:$author$project$Main$update,accept:$author$project$Main$acceptLoad,
    ok:$elm$core$Result$Ok,err:$elm$core$Result$Err,badStatus:$elm$http$Http$BadStatus,
    leads:$author$project$State$LeadsLoaded,users:$author$project$State$UsersLoaded,
    search:$author$project$State$SearchChanged,navigate:$author$project$State$UrlChanged,
    taskDone:$author$project$State$TaskStatusDone,page:$author$project$State$PageStep,
    operations:$author$project$State$OperationsLoaded,feature:$author$project$State$FeatureLoaded,
    featureSearch:$author$project$State$FeatureSearch,json:_Json_wrap,
    form:$author$project$Features$rowForm,defaults:$author$project$Features$defaults,
    get:$elm$core$Dict$get,inline:$author$project$State$InlineSection,inlineOwner:$author$project$State$InlineOwner,
    featureEdit:$author$project$State$FeatureEdit,featureDone:$author$project$State$FeatureDone,
    conflict:$author$project$State$ConflictLoaded,rebase:$author$project$State$ConflictRebase,
    none:$elm$core$Platform$Cmd$none,portalLoaded:$author$project$State$PortalLoaded,portalLogout:$author$project$State$PortalLogout,logout:$author$project$State$LogoutDone};\n`;
  const source=fs.readFileSync(output,'utf8').replace('_Platform_export({',expose+'_Platform_export({');
  const context={console:{log(){},warn(){}}};vm.runInNewContext(source,context);
  const e=context.stateTests;
  const initial=(pathname='/leads')=>e.A2(e.initial,{},e.url('http://ecc.test'+pathname).a);
  const update=(message,model)=>e.A2(e.update,message,model).a;
  const response=(model,constructor,value)=>e.A3(e.accept,model,constructor,e.ok(value));

  test('late search responses and repeated query values cannot replace current results',()=>{
    const original=initial();
    const late=response(original,e.leads,e.list([{id:1}]));
    const newer=update(e.search('new'),original);
    assert.equal(update(late,newer),newer);
    const repeated=update(e.search(''),newer);
    assert.equal(update(late,repeated),repeated);
    const current=e.list([{id:2}]);
    assert.equal(update(response(repeated,e.leads,current),repeated).leads,current);
  });
  test('navigation and mutations invalidate older loads',()=>{
    const original=initial();
    const late=response(original,e.leads,e.list([{id:1}]));
    const navigated=update(e.navigate(e.url('http://ecc.test/clients').a),original);
    assert.equal(update(late,navigated),navigated);
    const mutated=update(e.taskDone(e.ok({})),original);
    assert.equal(update(late,mutated),mutated);
  });
  test('search changes preserve in-flight staff directory loads',()=>{
    const original=initial();
    const users=e.list([{id:1,name:'Staff'}]);
    const loaded=response(original,e.users,users);
    const searched=update(e.search('new'),original);
    assert.equal(update(loaded,searched).users,users);
  });
  test('stale authentication errors are ignored and expiration rejects old staff data',()=>{
    const original={...initial(),user:{$:'Just',a:{id:1}},token:{$:'Just',a:'active-session'}};
    const failed=e.A3(e.accept,original,e.leads,e.err(e.badStatus(401)));
    const searched=update(e.search('new'),original);
    assert.equal(update(failed,searched),searched);
    const expired=update(failed,original);
    assert.equal(expired.user.$,'Nothing');
    const oldUsers=response(original,e.users,e.list([{id:1}]));
    assert.equal(update(oldUsers,expired),expired);
  });
  test('operational pagination rejects the old page and accepts the current page',()=>{
    const original=initial('/archive');
    const late=response(original,e.operations,e.list([{id:1}]));
    const page=update(e.page(1),original);
    assert.equal(page.pageOffset,50);
    assert.equal(update(late,page),page);
    const current=e.list([{id:51}]);
    assert.equal(update(response(page,e.operations,current),page).opsData,current);
  });
  test('document forms preserve revisions and scalar fields alongside nested versions',()=>{
    const form=e.form(e.json({id:9,title:'Passport',owner:'client:4',revision:7,versions:[{version:1,documentId:12}]}));
    assert.equal(e.A2(e.get,'expectedRevision',form).a,'7');
    assert.equal(e.A2(e.get,'owner',form).a,'client:4');
    assert.equal(e.A2(e.get,'request',form).a,'request:9');
    assert.equal(e.A2(e.get,'entity',e.defaults('merge')).a,'leads');
  });
  test('workspace search and pagination reject stale feature responses',()=>{
    const original=initial('/work/search');
    const late=response(original,e.feature,e.json({rows:[{id:1}],options:[]}));
    const searched=update(e.featureSearch('@view:9'),original);
    assert.equal(update(late,searched),searched);
    const page=update(e.page(1),searched);
    assert.equal(page.pageOffset,50);
    assert.equal(page.featureSearch,'@view:9');
    const current=e.json({rows:[{id:51}],options:[]});
    assert.equal(update(response(page,e.feature,current),page).opsData.a.a.id,51);
  });
  test('logout clears authenticator setup and private portal links',()=>{
    const original={...initial('/work/security'),featureData:e.json({private:'data'}),featureResult:e.json({secret:'private',url:'private-link'})};
    const loggedOut=update(e.logout(e.ok({})),original);
    assert.equal(loggedOut.user.$,'Nothing');
    assert.equal(loggedOut.featureResult.a,null);
    assert.equal(loggedOut.featureData.a,null);
  });
  test('portal logout rejects in-flight client data',()=>{
    const original=initial('/portal');
    const late=response(original,e.portalLoaded,e.json({client:[{name:'Private client'}]}));
    const signedOut=update(e.portalLogout,original);
    assert.equal(update(late,signedOut),signedOut);
    assert.equal(signedOut.portalData.a,null);
  });
  test('inline client and case scope changes reject previous panels',()=>{
    const original=initial('/clients/4');
    assert.equal(original.inlineOwner,'client:4');
    const late=response(original,e.feature,e.json({rows:[{id:1}],options:[]}));
    const docs=update(e.inline('documents'),original);
    assert.equal(docs.inlineSection,'documents');
    assert.equal(update(late,docs),docs);
    const caseScope=update(e.inlineOwner('case:9'),docs);
    assert.equal(caseScope.inlineOwner,'case:9');
    assert.equal(caseScope.pageOffset,0);
    assert.equal(e.A2(e.get,'owner',caseScope.featureForm).a,'case:9');
  });
  test('editing another row invalidates pending saves and records a baseline',()=>{
    const original=initial('/work/tasks');
    const late=response(original,e.featureDone,e.json({message:'Saved old task'}));
    const row=e.json({id:8,title:'New task',revision:5});
    const selected=update(e.featureEdit(row),original);
    assert.equal(e.A2(e.get,'title',selected.featureBaseline).a,'New task');
    assert.equal(update(late,selected),selected);
  });
  test('accepting a conflict keeps the draft and requires a separate save',()=>{
    const original=initial('/work/tasks');
    const selected=update(e.featureEdit(e.json({id:8,title:'My draft',revision:4})),original);
    const comparison={...selected,conflictKind:'tasks',conflictCurrent:e.json({id:8,title:'Colleague change',revision:7})};
    const result=e.A2(e.update,e.rebase,comparison);
    assert.equal(e.A2(e.get,'title',result.a.featureForm).a,'My draft');
    assert.equal(e.A2(e.get,'expectedRevision',result.a.featureForm).a,'7');
    assert.equal(result.b,e.none);
    assert.equal(result.a.conflictCurrent.a,null);
  });
  test('late conflict responses cannot restore client details after logout',()=>{
    const original=initial('/work/documents');
    const late=response(original,e.conflict,e.json({title:'Private client file',revision:7}));
    const signedOut=update(e.logout(e.ok({})),original);
    assert.equal(update(late,signedOut),signedOut);
    assert.equal(signedOut.conflictCurrent.a,null);
  });
} finally {fs.rmSync(directory,{recursive:true,force:true});}
