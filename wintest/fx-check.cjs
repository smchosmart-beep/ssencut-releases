// 쎈Cut 분위기 효과(1.2.0~) Windows 실기 확인 — 설치된 쎈Cut 화면(app\index.html)을 실제 Microsoft Edge(playwright-core, channel msedge)로 열어:
//  1) 효과 6개를 Edge가 투명하게 그리는지(빨간 바탕 위에 그려 빨강이 남는지 = 투명 유지)
//  2) 사진 + 효과 클립으로 실제 MP4 내보내기(Edge의 H.264 인코더) — 효과 있음/없음 시간 비교, 완성 MP4 저장
//  3) 화면 캡처(효과 탭·효과 설정)
// usage: node fx-check.cjs <설치 폴더> <결과 폴더>   (결과: fx-check.json, fx-export.mp4, fx-*.png)
'use strict';
const path = require('path'), fs = require('fs');
const { chromium } = require('playwright-core');
const [inst, out] = process.argv.slice(2);
(async () => {
  const result = { effects: [], export: null, errors: [] };
  const browser = await chromium.launch({ ...(process.env.CHROME ? { executablePath: process.env.CHROME, headless: true } : { channel: 'msedge', headless: false }), args: ['--autoplay-policy=no-user-gesture-required'] }); // CHROME: 리눅스에서 미리 돌려 보기용
  try {
    const page = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();
    page.on('pageerror', e => result.errors.push(e.message));
    const url = 'file:///' + path.join(inst, 'app', 'index.html').replace(/\\/g, '/') + '#ssenPort=1&ssenKey=test';
    await page.goto(url);
    await page.waitForFunction(() => window.SsenAuth && window.CutFx && typeof addFx === 'function' && document.querySelectorAll('#assetList .asset').length > 0, null, { timeout: 120000 });
    await page.evaluate(() => { SsenAuth.requireEdit = () => true; SsenAuth.canEdit = () => true; document.querySelectorAll('dialog[open]').forEach(d => d.close()); });
    result.version = await page.evaluate(() => document.title);
    // 1) 효과 6개 투명 그리기
    result.effects = await page.evaluate(async () => {
      const outList = [];
      for (const e of CutFx.list()) {
        const t0 = performance.now(), r = { id: e.id, name: e.name };
        try {
          if (e.code) { // 1.2.1~ 필름 질감: 파일 없이 화면이 그림
            const cv = document.createElement('canvas'); cv.width = 480; cv.height = 270; const g = cv.getContext('2d'); g.fillStyle = '#808080'; g.fillRect(0, 0, 480, 270);
            CutRender.fx(g, { id: 'x', effectId: e.id, start: 0, duration: 8, in: 0, opacity: 1, fadeIn: 0, fadeOut: 0 }, 3, 480, 270, new Map());
            const d = g.getImageData(0, 0, 480, 270).data; let ch = 0; for (let i = 0; i < d.length; i += 4) if (d[i] !== 128) ch++;
            r.code = true; r.drawn = +(ch / (d.length / 4)).toFixed(3); r.clear = 0; r.seekMs = 0; r.ok = r.drawn > 0.3; r.ms = Math.round(performance.now() - t0); outList.push(r); continue;
          }
          const v = document.createElement('video'); v.muted = true; v.src = await CutFx.url(e.id);
          await new Promise((ok, no) => { v.onloadeddata = ok; v.onerror = () => no(Error('video error ' + (v.error && v.error.code))); setTimeout(() => no(Error('load timeout')), 20000); });
          let seekMs = 0;
          for (const t of [1, 2, 3, 4, 5, 6, 7]) { const s = performance.now(); await new Promise(ok => { v.onseeked = ok; v.currentTime = t; }); seekMs += performance.now() - s; }
          const cv = document.createElement('canvas'); cv.width = 480; cv.height = 270; const g = cv.getContext('2d');
          let clear = 0, drawn = 0, n = 0;
          for (const t of [1, 3, 5]) { await new Promise(ok => { v.onseeked = ok; v.currentTime = t; }); g.globalCompositeOperation = 'source-over'; g.fillStyle = '#ff0000'; g.fillRect(0, 0, 480, 270); g.drawImage(v, 0, 0, 480, 270);
            const d = g.getImageData(0, 0, 480, 270).data; for (let i = 0; i < d.length; i += 4) { n++; if (d[i] === 255 && d[i + 1] === 0 && d[i + 2] === 0) clear++; else drawn++; } }
          r.clear = +(clear / n).toFixed(3); r.drawn = +(drawn / n).toFixed(4); r.seekMs = Math.round(seekMs / 7); r.width = v.videoWidth; r.height = v.videoHeight;
          // 투명이 살아 있으면 빨간 바탕이 대부분 그대로(필름 질감은 아주 옅어 대부분 거의 빨강이라 '그림' 비율이 높을 수 있음)
          r.ok = v.videoWidth === 1920 && (r.clear > 0.3 || (e.id === 'film-grain' && r.drawn > 0));
          new VideoFrame(cv, { timestamp: 0 }).close(); r.frameOk = true;
        } catch (err) { r.ok = false; r.err = String(err && err.message || err); }
        r.ms = Math.round(performance.now() - t0); outList.push(r);
      }
      return outList;
    });
    // 2) 실제 내보내기: 사진 1장(4초) + 종이 꽃가루 0~4초
    await page.evaluate(async () => {
      const cv = document.createElement('canvas'); cv.width = 1600; cv.height = 900; const g = cv.getContext('2d'); const gr = g.createLinearGradient(0, 0, 1600, 900); gr.addColorStop(0, '#3a6f8f'); gr.addColorStop(1, '#1e3932'); g.fillStyle = gr; g.fillRect(0, 0, 1600, 900);
      const blob = await new Promise(r => cv.toBlob(r, 'image/png')); await importFiles([new File([blob], 'fx-test.png', { type: 'image/png' })]);
      const a = [...assets.values()].find(x => x.name === 'fx-test.png'); addAsset(a.id); time = 0; addFx('paper-confetti', null, 0);
      const c = p.clips.find(x => x.type === 'fx'); mutate(() => { c.duration = 4; });
    });
    await page.click('[data-tab="fx"]').catch(() => {});
    await page.waitForTimeout(1500); await page.screenshot({ path: path.join(out, 'fx-editor.png') });
    const exportOnce = async () => page.evaluate(async () => {
      document.querySelectorAll('dialog[open]').forEach(d => d.close()); $('exportBtn').click(); const s = $('exportSize'); s.value = 'pc'; s.dispatchEvent(new Event('change'));
      const t0 = performance.now(); await exportMP4(); const r = { status: $('exportStatus').textContent, toast: $('toast').textContent, ms: Math.round(performance.now() - t0), bytes: lastResult && lastResult.blob ? lastResult.blob.size : 0 }; return r;
    });
    const withFx = await exportOnce();
    const mp4 = await page.evaluate(async () => { if (!lastResult) return null; const b = new Uint8Array(await lastResult.blob.arrayBuffer()); let s = ''; for (let i = 0; i < b.length; i += 32768) s += String.fromCharCode.apply(null, b.subarray(i, i + 32768)); return btoa(s); });
    if (mp4) fs.writeFileSync(path.join(out, 'fx-export.mp4'), Buffer.from(mp4, 'base64'));
    await page.evaluate(() => { document.querySelectorAll('dialog[open]').forEach(d => d.close()); const c = p.clips.find(x => x.type === 'fx'); mutate(() => { c.opacity = 0; }); });
    const noFx = await exportOnce();
    result.export = { withFx, noFx, ok: /완성/.test(withFx.status) && withFx.bytes > 10000 };
  } catch (e) { result.errors.push('runner: ' + (e && e.message || e)); }
  finally { await browser.close(); }
  fs.writeFileSync(path.join(out, 'fx-check.json'), JSON.stringify(result, null, 1));
  console.log('FXRESULT ' + JSON.stringify(result));
})();
