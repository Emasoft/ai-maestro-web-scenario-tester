// region-capture.js — DOM/ARIA-guided, token-cheap capture for UI scenario verification.
//
// Paste the function(s) you need into your dev-browser script (the QuickJS sandbox
// runs this against the live Playwright `page`). Read once, reuse across steps.
//
// Uses only portable primitives — page.evaluate (DOM/ARIA resolution) and
// page.screenshot({clip}). The newer locator APIs (locator.ariaSnapshot,
// getByRole) are used ONLY on a try/catch fast path, with a page.evaluate
// fallback, so everything works regardless of the dev-browser build.
//
// target shapes accepted everywhere:
//   { selector: "#agent-toolbar" }     CSS — most precise
//   { role: "dialog", name: "Delete" } ARIA role (+ optional accessible-name substring)
//   { text: "Delete Forever" }         visible-text substring

// --- bbox resolution via the LIVE DOM/ARIA tree -----------------------------
async function boxOf(page, target) {
  return await page.evaluate((t) => {
    const implicitRole = (e) => ({
      button:'button', a:'link', nav:'navigation', main:'main', header:'banner',
      footer:'contentinfo', aside:'complementary', dialog:'dialog',
      input:'textbox', select:'combobox',
    })[e.tagName.toLowerCase()] || e.getAttribute('role') || '';
    const vis = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    let el = null;
    if (t.selector) {
      el = document.querySelector(t.selector);
    } else if (t.role) {
      const c = [...document.querySelectorAll('*')].filter((e) => {
        if ((e.getAttribute('role') || implicitRole(e)) !== t.role) return false;
        if (t.name) return ((e.getAttribute('aria-label') || e.textContent || '').trim()).includes(t.name);
        return true;
      });
      el = c.find(vis) || c[0];
    } else if (t.text) {
      el = [...document.querySelectorAll('*')].find((e) => vis(e) && (e.textContent || '').trim().includes(t.text));
    }
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x, y: r.y, width: r.width, height: r.height };
  }, target);
}

function clipWithMargin(box, vp, margin) {
  const x = Math.max(0, box.x - margin), y = Math.max(0, box.y - margin);
  return {
    x, y,
    width:  Math.min(vp.width  - x, box.width  + 2 * margin),
    height: Math.min(vp.height - y, box.height + 2 * margin),
  };
}

// --- (1) SCOPED aria snapshot — TEXT, the DEFAULT for verification ----------
// Cheapest observation: 0.2-2K tokens vs 5-20K for a full-page snapshotForAI().
async function scopedAria(page, target) {
  if (target.selector && page.locator) {
    try { return await page.locator(target.selector).ariaSnapshot(); } catch (_) { /* fall through */ }
  }
  return await page.evaluate((t) => {
    const root = t.selector ? document.querySelector(t.selector) : document.body;
    if (!root) return null;
    const node = (e, d = 0) => {
      const role = e.getAttribute('role') || e.tagName.toLowerCase();
      const name = (e.getAttribute('aria-label') || '').trim()
        || (e.children.length === 0 ? (e.textContent || '').trim().slice(0, 80) : '');
      const st = ['disabled','checked','expanded','selected','hidden']
        .filter((s) => e.hasAttribute('aria-' + s) || e.hasAttribute(s))
        .map((s) => `${s}=${e.getAttribute('aria-' + s) ?? 'true'}`).join(',');
      let line = '  '.repeat(d) + role + (name ? ` "${name}"` : '') + (st ? ` [${st}]` : '');
      for (const c of e.children) { const sub = node(c, d + 1); if (sub) line += '\n' + sub; }
      return line;
    };
    return node(root);
  }, target);
}

// --- (2) Clipped screenshot of ONE region -----------------------------------
// Token cost ~ (w*h)/750 -> typically 16-320 vs ~1365 for a full page.
// margin: ~16 for truncation/gradient/focus checks; ~32 for bleed-out/overflow.
async function captureRegion(page, target, { margin = 24, path } = {}) {
  const box = await boxOf(page, target);
  if (!box) throw new Error('region-capture: target not found/visible: ' + JSON.stringify(target));
  const vp = (await page.viewportSize?.()) || { width: 1280, height: 800 };
  return page.screenshot({ clip: clipWithMargin(box, vp, margin), path }); // omit path -> buffer
}

// --- (3) Global check, decomposed by ARIA landmarks -------------------------
// One small clip per landmark instead of a single full-page shot.
async function captureLandmarks(page, { margin = 16, dir, runTag } = {}) {
  const roles = ['banner', 'navigation', 'main', 'complementary', 'contentinfo', 'dialog'];
  const vp = (await page.viewportSize?.()) || { width: 1280, height: 800 };
  const out = [];
  for (const role of roles) {
    const box = await boxOf(page, { role });
    if (!box) continue;
    const path = dir ? `${dir}/${runTag || 'lm'}_${role}.png` : undefined;
    await page.screenshot({ clip: clipWithMargin(box, vp, margin), path });
    out.push({ role, path });
  }
  return out;
}

// Export style is irrelevant in the QuickJS sandbox (paste + call directly), but
// kept for clarity / reuse in a Node test harness.
if (typeof module !== 'undefined') module.exports = { boxOf, clipWithMargin, scopedAria, captureRegion, captureLandmarks };
