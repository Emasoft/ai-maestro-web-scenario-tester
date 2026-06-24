// step-driver.js — run MANY scenario steps in ONE dev-browser call (one turn).
//
// Cost = turns x per-turn-context. Each dev-browser Bash call is one TURN, and a
// scenario step is usually snapshot->act->screenshot->verify = 3-4 turns. This
// driver runs a declarative list of {action, assertion} steps sequentially inside
// ONE sandbox execution (one turn), STOPPING at the first failed assertion so
// nothing runs blind past a break — FIX-AS-YOU-GO stays intact.
//
// Paste into your dev-browser `<<'EOF' ... EOF` script and call against `page`.
// Returns a COMPACT log: [{i, do, ok, detail?}] — never raw snapshots.
//
// Step shape:
//   { do:'click',  selector:'#new-agent' , expect:{visible:'[role=dialog]'} }
//   { do:'fill',   selector:'#name', value:'scen018-x', expect:{value:{selector:'#name',equals:'scen018-x'}} }
//   { do:'press',  selector:'#name', key:'Enter' }
//   { do:'goto',   url:'http://localhost:3000/settings' , expect:{text:'Settings'} }
//   { do:'wait',   ms:400 }                        // or expect:{visible:sel} to wait on state
//   { do:'check',  expect:{text:'created'} }        // pure assertion, no action
// Actions use a CSS `selector` (get it from your snapshot). Read-only `expect`
// also accepts {role,name} via the DOM. Defaults: timeout 8000ms per step.

async function _present(page, expect, timeout) {
  // visible / hidden by selector
  if (expect.visible)  return page.waitForSelector(expect.visible, { state: 'visible', timeout });
  if (expect.hidden)   return page.waitForSelector(expect.hidden,  { state: 'hidden',  timeout });
  // text anywhere on the page (polled)
  if (expect.text) {
    return page.waitForFunction(
      (t) => (document.body && document.body.innerText || '').includes(t),
      expect.text, { timeout },
    );
  }
  // input value equals
  if (expect.value) {
    const { selector, equals } = expect.value;
    return page.waitForFunction(
      (a) => { const el = document.querySelector(a.s); return !!el && (el.value ?? el.textContent ?? '') === a.v; },
      { s: selector, v: equals }, { timeout },
    );
  }
  // ARIA role (+ optional accessible-name substring) present & visible
  if (expect.role) {
    return page.waitForFunction((a) => {
      const implicit = (e) => ({button:'button',a:'link',nav:'navigation',main:'main',
        header:'banner',footer:'contentinfo',aside:'complementary',dialog:'dialog'})[e.tagName.toLowerCase()] || e.getAttribute('role') || '';
      return [...document.querySelectorAll('*')].some((e) => {
        if ((e.getAttribute('role') || implicit(e)) !== a.role) return false;
        if (a.name && !((e.getAttribute('aria-label') || e.textContent || '').includes(a.name))) return false;
        const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0;
      });
    }, { role: expect.role, name: expect.name || '' }, { timeout });
  }
  throw new Error('unknown expect: ' + JSON.stringify(expect));
}

async function _act(page, s, timeout) {
  switch (s.do) {
    case 'click': return page.click(s.selector, { timeout });
    case 'fill':  return page.fill(s.selector, s.value ?? '', { timeout });
    case 'press': return page.press(s.selector, s.key, { timeout });
    case 'goto':  return page.goto(s.url, { waitUntil: 'domcontentloaded', timeout });
    case 'wait':  return s.ms ? page.waitForTimeout(s.ms) : Promise.resolve();
    case 'check': return Promise.resolve(); // assertion-only step
    default: throw new Error('unknown action: ' + s.do);
  }
}

async function runSteps(page, steps, { timeout = 8000 } = {}) {
  const log = [];
  for (let i = 0; i < steps.length; i++) {
    const s = steps[i];
    try {
      await _act(page, s, timeout);
      if (s.expect) await _present(page, s.expect, timeout);
      log.push({ i, do: s.do, ok: true });
    } catch (e) {
      log.push({ i, do: s.do, ok: false, detail: String((e && e.message) || e).replace(/\s+/g, ' ').slice(0, 180) });
      break; // STOP on first failure — the agent diagnoses from {i, detail}, not a re-run
    }
  }
  return log;
}

if (typeof module !== 'undefined') module.exports = { runSteps };
