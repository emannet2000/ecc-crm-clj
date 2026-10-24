const {test}=require('node:test');
const assert=require('node:assert/strict');
const {Browser}=require('../../api/test/live-browser-driver.cjs');

test('live XTDB journey covers conversion, templates, portal acceptance, finance and reconciliation', {timeout:120000,skip:!process.env.ECC_TEST_URL}, async()=>{
  const browser=new Browser();
  // Real XTDB queries and password checks can take longer on a busy CI host.
  const wait=browser.wait.bind(browser);
  browser.wait=async expression=>{
    for(let attempt=0;attempt<6;attempt++){
      try{return await wait(expression);}catch(error){if(attempt===5||browser.failure)throw error;}
    }
  };
  const fill=async(name,text)=>{await browser.evaluate(`(()=>{const e=document.querySelector('[name="${name}"]');e.focus();e.select();})()`);await browser.send('Input.insertText',{text});await browser.evaluate('new Promise(r=>setTimeout(r,80))');};
  const api=async(method,url,data)=>{
    const response=await browser.evaluate(`fetch(${JSON.stringify(url)},{method:${JSON.stringify(method)},credentials:'same-origin',headers:{'content-type':'application/json'},${data===undefined?'':'body:'+JSON.stringify(JSON.stringify(data))}}).then(async r=>({status:r.status,body:await r.json()}))`);
    assert.equal(response.status,200,`${method} ${url}: ${JSON.stringify(response.body)}`);return response.body;
  };
  try{
    await browser.start(process.env.ECC_TEST_URL);
    await browser.wait('!!document.querySelector("input[name=email]")');
    await fill('email','journey@example.com');await fill('password',process.env.ECC_TEST_PASSWORD);
    await browser.clickText('Sign in');await browser.wait('document.body.innerText.includes("Sign out")');
    await browser.clickText('Leads');await browser.wait('!document.body.innerText.includes("Loading…")');
    await browser.clickText('+ New record');await fill('fullName','Journey Student');await fill('email','student@example.com');
    await browser.clickText('Save');await browser.wait('!!document.querySelector("table")?.innerText.includes("Journey Student")');
    await browser.clickText('Convert');await browser.wait('!!document.querySelector("table")?.innerText.includes("Converted")');
    const clients=await api('GET','/api/clients');assert.equal(clients.total,1);const client=clients.rows[0];
    const detail=await api('GET',`/api/clients/${client.id}`);assert.equal(detail.cases.length,1);
    await api('POST',`/api/clients/${client.id}/notes`,{note:'Private staff history'});
    await api('PUT',`/api/clients/${client.id}/profile`,{nationality:'Filipino',passportNumber:'FIXTURE-ONLY'});
    const profile=await api('GET',`/api/clients/${client.id}/profile`);assert.equal(profile.nationality,'Filipino');
    const template=await api('POST','/api/workspace/checklist-templates/save',{title:'Visa checklist',items:[{title:'Passport',required:true},{title:'Transcript',required:true}]});
    const checklist=await api('POST','/api/workspace/applications/checklist',{applicationId:detail.cases[0].id,templateId:template.id});assert.equal(checklist.length,2);
    const upload=await api('POST',`/api/clients/${client.id}/documents`,{filename:'fixture.txt',content:Buffer.from('journey document').toString('base64'),requestId:checklist[0].id});assert.equal(upload.scanStatus,'Quarantined');
    assert.equal(await browser.evaluate(`fetch('/api/documents/${upload.id}/download').then(r=>r.status)`),409);
    const commercial={clientId:client.id,caseId:detail.cases[0].id,title:'Agreement',body:'Service terms',amount:'100',currency:'PHP',validUntil:'2027-12-31'};
    const proposal=await api('POST','/api/workspace/proposals/save',commercial);await api('POST','/api/workspace/proposals/issue',{id:proposal.id,revision:proposal.revision});
    const contract=await api('POST','/api/workspace/contracts/save',commercial);await api('POST','/api/workspace/contracts/issue',{id:contract.id,revision:contract.revision});
    const invitation=await api('POST','/api/workspace/portal/create',{clientId:client.id});await api('POST','/api/portal/exchange',{token:invitation.token});
    const portal=await api('GET','/api/portal');assert.equal(portal.client.id,client.id);assert.ok(!JSON.stringify(portal).includes('Private staff history'));assert.ok(!JSON.stringify(portal).includes('FIXTURE-ONLY'));
    await api('POST',`/api/portal/commercial/contracts/${contract.id}/accept`,{name:'Journey Student'});
    await api('POST','/api/workspace/contracts/complete',{id:contract.id});
    const invoice=await api('POST','/api/workspace/invoices/save',{clientId:client.id,caseId:detail.cases[0].id,title:'Tuition services',description:'Application fee',subtotal:'100',currency:'PHP',dueDate:'2027-12-31'});
    await api('POST','/api/workspace/invoices/send',{id:invoice.id});
    const paymentInput={invoiceId:invoice.id,amount:'100',paidOn:new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Manila'}),method:'Bank transfer',reference:'BANK-JOURNEY',submissionKey:'journey-payment'};
    const receipt=await api('POST','/api/workspace/payments/record',paymentInput);const duplicate=await api('POST','/api/workspace/payments/record',paymentInput);assert.equal(receipt.id,duplicate.id);
    const banks=await api('POST','/api/workspace/reconciliation/import',{account:'Fixture account',csv:`date,amount,currency,reference\n${paymentInput.paidOn},100,PHP,BANK-JOURNEY\n`});
    await api('POST','/api/workspace/reconciliation/match',{id:banks[0].id,kind:'payment',entryId:receipt.id});
    const balances=await api('GET','/api/workspace/balances');assert.equal(balances.rows[0].balance,'0.00');
    assert.equal(await browser.evaluate(`fetch('/api/portal/receipts/${receipt.id}/download').then(r=>r.status)`),200);
    assert.equal(await browser.evaluate(`fetch('/api/workspace/finance-export/cashflow').then(r=>r.status)`),200);
    await browser.clickText('Clients');await browser.wait('!!document.querySelector("table")?.innerText.includes("Journey Student")');
    await browser.screenshot('ecc-clojure-live-journey.png');
    const publicLink=await api('POST','/api/workspace/portal/create',{clientId:client.id});
    await browser.send('Page.navigate',{url:publicLink.url});
    await browser.wait('document.body.innerText.includes("Your client portal") && document.body.innerText.includes("Journey Student")');
    assert.ok(!(await browser.evaluate('document.body.innerText')).includes('Journey Admin'));
    assert.ok(!(await browser.evaluate('document.body.innerText')).includes('Private staff history'));
    await browser.clickText('Close portal');await browser.wait('document.body.innerText.includes("Portal session closed")');
    assert.equal(await browser.evaluate(`fetch('/api/portal').then(r=>r.status)`),401);
    await browser.send('Page.navigate',{url:process.env.ECC_TEST_URL+'/#/clients'});
    await browser.wait('document.body.innerText.includes("Sign out") && !!document.querySelector("table")?.innerText.includes("Journey Student")');
    await browser.clickText('Sign out');await browser.wait('!!document.querySelector("input[name=password]")');
    assert.equal(await browser.evaluate(`fetch('/api/clients').then(r=>r.status)`),401);
    assert.deepEqual(browser.errors,[]);
  }finally{await browser.close();}
});
