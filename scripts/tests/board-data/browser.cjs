// Isolated browser test. Every request is intercepted; no node/network access.
const assert=require('node:assert/strict'), path=require('node:path');
const {spawnSync}=require('node:child_process');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
(async()=>{
 const browser=await chromium.launch({headless:true, ...(process.env.CHROMIUM_PATH ? {executablePath:process.env.CHROMIUM_PATH}:{})});
 const context=await browser.newContext(); const page=await context.newPage();
 const responses=[], errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await context.route('**/*',async route=>{
  const req=route.request(), u=new URL(req.url());
  assert.equal(u.hostname,'aredn-fixture.invalid');
  const body=req.postData()||'';
  const input={body,env:{PATH_INFO:u.pathname.replace(/^\/a/,'')||'/',REQUEST_METHOD:req.method(),CONTENT_TYPE:req.headers()['content-type']||'',CONTENT_LENGTH:String(Buffer.byteLength(body)),headers:req.headers()}};
  const p=spawnSync('python3',[path.join(__dirname,'web-fixture.py')],{input:JSON.stringify(input),encoding:'utf8',env:process.env});
  assert.equal(p.status,0,p.stderr);
  const result=JSON.parse(p.stdout); responses.push({method:req.method(),path:u.pathname,calls:result.calls});
  const split=result.response.indexOf('\r\n\r\n'), head=result.response.slice(0,split).split('\r\n'), headers={};
  const status=Number(head.shift().match(/^Status: (\d+)/)[1]);
  for(const line of head){const i=line.indexOf(':');if(i>=0)headers[line.slice(0,i).toLowerCase()]=line.slice(i+1).trim();}
  delete headers['content-length'];
  await route.fulfill({status,headers,body:result.response.slice(split+4)});
 });
 await page.goto('http://aredn-fixture.invalid/a/');
 assert.equal(await page.locator('#board-error').count(),0);
 await page.locator('#password').fill('wrong');
 await Promise.all([page.waitForNavigation(),page.getByRole('button',{name:'Sign in'}).click()]);
 assert.equal(await page.getByRole('alert').innerText(),'Sign-in failed.');
 await page.locator('#password').fill('correct password+');
 await Promise.all([page.waitForNavigation(),page.getByRole('button',{name:'Sign in'}).click()]);
 assert.equal(await page.locator('#board-error').innerText(),'Board metadata is not valid JSON');
 assert.equal(await page.locator('#password').count(),0);
 await page.reload();
 assert.equal(await page.locator('#board-error').count(),1);
 const denied=await page.evaluate(async()=>{const r=await fetch('/a/status/e/network',{method:'PUT',body:'lan_ip=192.0.2.1'});return r.status;});
 assert.equal(denied,503);
 assert.equal(errors.length,0);
 assert(responses.every(r=>r.calls.configuration===0&&r.calls.radio===0));
 console.log(JSON.stringify({browser:browser.version(),passed:true,checks:['anonymous_login','incorrect_password','ordinary_form_correct_password_with_space_and_plus','authenticated_cookie_reload','configuration_put_blocked','no_page_errors','no_radio_or_config_calls'],requests:responses},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
