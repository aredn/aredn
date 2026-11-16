// Exact native-rendered time area and repository HTMX. All requests intercepted.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const output=path.resolve(process.env.GPS_OUTPUT || 'results/time-ui');
const cases=JSON.parse(fs.readFileSync(path.join(output,'render-cases.json'),'utf8'));
(async()=>{
  const browser=await chromium.launch({executablePath:process.env.CHROMIUM || '/usr/bin/chromium',headless:true,args:['--no-sandbox']});
  const errors=[],rows=[];
  try {
    for(const authenticated of [true,false]) for(const width of [960,375]) {
      const page=await browser.newPage({viewport:{width,height:950},deviceScaleFactor:1});
      page.on('pageerror',e=>errors.push(e.message));
      await page.route('**/*',r=>r.abort());
      for(const test of cases) for(const theme of ['light','dark','high-contrast','color-blind']) {
        await page.setContent(fs.readFileSync(path.join(output,`${test.name}.html`),'utf8'));
        if(!authenticated) await page.evaluate(()=>document.body.classList.remove('authenticated'));
        await page.addStyleTag({content:fs.readFileSync(path.join(output,'themes',`${theme}.css`),'utf8')});
        const badge=page.locator('.time-sync-status');
        assert.equal(await badge.count(),1);
        assert.equal(await badge.textContent(),test.label);
        const info=await badge.evaluate(e=>{
          const r=e.getBoundingClientRect(),s=getComputedStyle(e);
          return {left:r.left,right:r.right,background:s.backgroundColor,title:e.title,label:e.getAttribute('aria-label'),
            role:e.getAttribute('role'),pageWidth:document.documentElement.scrollWidth};
        });
        assert.equal(info.role,'status');assert.equal(info.title,info.label);assert.ok(info.title.length>10);
        assert.ok(info.left>=0 && info.right<=width,`badge overflow ${test.name} at ${width}`);
        assert.ok(info.pageWidth<=width,`page overflow ${test.name} at ${width}`);
        assert.equal(await page.locator('.time-sync-source').textContent(),`Source: ${test.source}`);
        const expected=await page.evaluate(state=>{
          const e=document.createElement('span');
          e.style.backgroundColor=state==='pending'?'#f4c542':getComputedStyle(document.documentElement).getPropertyValue(state==='locked'?'--firmware-status-bg-color-positive':'--firmware-status-bg-color-negative');
          document.body.append(e);const c=getComputedStyle(e).backgroundColor;e.remove();return c;
        },test.state);
        assert.equal(info.background,expected);
        if(test.name==='ntp-and-gps') assert.equal(await page.locator('.gps-lock-status').textContent(),'GPS LOCK · NETWORK');
        else assert.equal(await page.locator('.gps-lock-status').count(),0);
        rows.push({authenticated,width,name:test.name,theme,passed:true});
        if(authenticated && theme==='light' && (width===960 || test.name==='ntp-synced'))
          await page.locator('article').screenshot({path:path.join(output,`time-${test.name}-${width}.png`)});
      }
      await page.close();
    }
    const page=await browser.newPage({viewport:{width:960,height:950}});
    page.on('pageerror',e=>errors.push(e.message));
    let refreshes=0,edits=0;
    await page.clock.install();
    await page.route('**/*',async route=>{
      const p=new URL(route.request().url()).pathname;
      if(p==='/') return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(output,'gps-locked.html'),'utf8').replace('</head>','<script src="/htmx.js"></script></head>')});
      if(p==='/htmx.js') return route.fulfill({contentType:'application/javascript',body:fs.readFileSync(path.join(output,'htmx.min.js'))});
      if(p==='/u-health') {refreshes++;return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(output,refreshes===1?'gps-waiting-partial.html':'gps-error-partial.html'),'utf8')});}
      if(p==='/status/e/time') {edits++;return route.fulfill({contentType:'text/html',body:'<div>Time settings fixture</div>'});}
      throw new Error(`Unexpected request ${route.request().url()}`);
    });
    await page.goto('http://time-ui.test/');
    await page.waitForFunction(()=>window.htmx && document.querySelector('.time-sync-status.locked'));
    await page.locator('#health .ctrl').click();
    await page.locator('#ctrl-modal').getByText('Time settings fixture').waitFor();
    assert.equal(edits,1);
    await page.clock.fastForward(30100);await page.locator('.time-sync-status.pending').waitFor();
    await page.clock.fastForward(30100);await page.locator('.time-sync-status.error').waitFor();
    assert.equal(refreshes,2);assert.deepEqual(errors,[]);
    fs.writeFileSync(path.join(output,'browser-summary.json'),JSON.stringify({viewportThemeCases:rows.length,rows,htmxRefreshes:refreshes,timeSettingsRequests:edits,pageErrors:errors},null,2)+'\n');
    console.log(`PASS: ${rows.length} time-area browser combinations; 2 HTMX refreshes; time-settings click preserved; zero page errors`);
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
