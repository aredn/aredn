// Exact native-rendered time area and repository HTMX. All requests intercepted.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const output=path.resolve(process.env.GPS_OUTPUT || 'results/time-ui');
const cases=JSON.parse(fs.readFileSync(path.join(output,'render-cases.json'),'utf8'));
assert.deepEqual([...new Set(cases.map(test=>test.label))].sort(),
  ['LOCKED · GPS','WAITING · GPS','ERROR · GPS','SYNCED · NTP','UNSYNCED · NTP','STATUS UNKNOWN'].sort());
(async()=>{
  const browser=await chromium.launch({executablePath:process.env.CHROMIUM || '/usr/bin/chromium',headless:true,args:['--no-sandbox']});
  const errors=[],rows=[],popupRows=[];
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
        assert.equal(await page.locator('.time-sync-source,.time-sync-detail').count(),0);
        assert.ok(info.title.includes(`Source: ${test.source}`));
        for(const text of test.details) assert.ok(info.title.includes(text),`missing hover detail ${text} in ${test.name}`);
        const expected=await page.evaluate(state=>{
          const e=document.createElement('span');
          e.style.backgroundColor=state==='pending'?'#f4c542':getComputedStyle(document.documentElement).getPropertyValue(state==='locked'?'--firmware-status-bg-color-positive':'--firmware-status-bg-color-negative');
          document.body.append(e);const c=getComputedStyle(e).backgroundColor;e.remove();return c;
        },test.state);
        assert.equal(info.background,expected);
        if(test.gpsLabel) {
          const gps=page.locator('.gps-lock-status');
          assert.equal(await gps.textContent(),test.gpsLabel.split(' · ')[0]);
          assert.ok(await gps.evaluate((e,state)=>e.classList.contains(state),test.gpsState));
          for(const text of test.gpsDetails) assert.ok((await gps.getAttribute('title')).includes(text));
        } else assert.equal(await page.locator('.gps-lock-status').count(),0);
        rows.push({authenticated,width,name:test.name,theme,passed:true});
        if(authenticated && theme==='light' && (width===960 || ['ntp-synced','gps-stale','ntp-status-old','ntp-success-old'].includes(test.name)))
          await page.locator('article').screenshot({path:path.join(output,`time-${test.name}-${width}.png`)});
        if(authenticated) {
          await page.evaluate(({body,mobile})=>{
            document.body.classList.toggle('mobile',mobile);
            const dialog=document.querySelector('#ctrl-modal');dialog.innerHTML=body;dialog.showModal();
          },{body:fs.readFileSync(path.join(output,`${test.name}-popup.html`),'utf8'),mobile:width===375});
          const details=page.locator('.time-status-details');
          await details.scrollIntoViewIfNeeded();
          assert.ok((await details.textContent()).includes(test.source));
          assert.ok((await details.textContent()).includes(test.label));
          for(const cell of await details.locator('.i').all()) {
            const rect=await cell.boundingBox();
            assert.ok(rect.x>=0 && rect.x+rect.width<=width,`popup field clipped ${test.name} at ${width}`);
          }
          assert.equal(await page.locator('[name=ntp_server]').inputValue(),'aredn.pool.ntp.org');
          popupRows.push({width,name:test.name,theme,passed:true});
          if(theme==='light' && ['gps-waiting','ntp-hostname','ntp-and-gps'].includes(test.name)) {
            await page.locator('#ctrl-modal').screenshot({path:path.join(output,`popup-${test.name}-${width}-3col.png`)});
            const alternate=await page.addStyleTag({content:'#ctrl-modal .time-status-details .cols{grid-template-columns:repeat(2,minmax(0,1fr))}'});
            await page.locator('#ctrl-modal').screenshot({path:path.join(output,`popup-${test.name}-${width}-2col.png`)});
            await alternate.evaluate(node=>node.remove());
          }
          await page.evaluate(()=>{const dialog=document.querySelector('#ctrl-modal');dialog.close();dialog.innerHTML='';document.body.classList.remove('mobile');});
        }
      }
      await page.close();
    }
    const page=await browser.newPage({viewport:{width:960,height:950}});
    page.on('pageerror',e=>errors.push(e.message));
    let refreshes=0,edits=0,popupRefreshes=0,settingsWrites=0;
    await page.clock.install();
    await page.route('**/*',async route=>{
      const p=new URL(route.request().url()).pathname;
      if(p==='/') return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(output,'gps-locked.html'),'utf8').replace('</head>','<script src="/htmx.js"></script></head>')});
      if(p==='/htmx.js') return route.fulfill({contentType:'application/javascript',body:fs.readFileSync(path.join(output,'htmx.min.js'))});
      if(p==='/u-health') {const next=['gps-waiting','gps-error','gps-stale'][refreshes++];assert.ok(next);return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(output,`${next}-partial.html`),'utf8')});}
      if(p==='/status/e/time') {
        if(route.request().method()==='PUT') {
          assert.equal(new URLSearchParams(route.request().postData()).get('ntp_mode'),'1');settingsWrites++;
          return route.fulfill({contentType:'text/html',body:''});
        }
        edits++;return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(output,'gps-locked-popup.html'))});
      }
      if(p==='/u-time-status') {
        const next=['gps-waiting','gps-error','gps-stale'][popupRefreshes++];assert.ok(next);
        return route.fulfill({contentType:'text/html',body:fs.readFileSync(path.join(output,`${next}-details.html`))});
      }
      throw new Error(`Unexpected request ${route.request().url()}`);
    });
    await page.goto('http://time-ui.test/');
    await page.waitForFunction(()=>window.htmx && document.querySelector('.time-sync-status.locked'));
    await page.locator('#health .ctrl').click();
    await page.locator('#ctrl-modal .time-status-details').waitFor();
    assert.equal(edits,1);
    await page.locator('[name=ntp_mode]').selectOption('1');
    await page.waitForFunction(()=>document.querySelector('[name=ntp_mode]').value==='1');
    await page.clock.fastForward(30100);await page.locator('.time-sync-status.pending').waitFor();
    await page.clock.fastForward(30100);await page.locator('.time-sync-status.error').waitFor();
    await page.clock.fastForward(30100);await page.locator('.time-sync-status.pending').waitFor();
    assert.equal(await page.locator('.time-sync-status').textContent(),'STATUS UNKNOWN');
    await page.locator('.time-status-details').getByText('STATUS UNKNOWN',{exact:true}).waitFor();
    assert.ok((await page.locator('.time-status-details').textContent()).includes('200 seconds'));
    assert.equal(await page.locator('[name=ntp_mode]').inputValue(),'1');
    assert.equal(settingsWrites,1);assert.equal(refreshes,3);assert.equal(popupRefreshes,3);assert.deepEqual(errors,[]);
    fs.writeFileSync(path.join(output,'browser-summary.json'),JSON.stringify({viewportThemeCases:rows.length,rows,popupCases:popupRows.length,popupRows,htmxRefreshes:refreshes,popupRefreshes,timeSettingsRequests:edits,settingsWrites,stagedInputPreserved:true,pageErrors:errors},null,2)+'\n');
    console.log(`PASS: ${rows.length} compact-status and ${popupRows.length} popup browser combinations; 3 status + 3 popup HTMX refreshes; staged input preserved; zero page errors`);
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
