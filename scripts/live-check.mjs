// UPZONE — check of the site that is really online. Opens the public pages like a phone and a computer would, follows
// their links, tries the sign-in screen, and, when test accounts are given, signs in and walks through their screens.
//
// It only looks: the single form it ever sends is the sign-in form. It never scans, writes, pays, deletes or reports.
//
//   node scripts/live-check.mjs
//
// Settings (environment variables), all optional:
//   LIVE_CHECK_URL                      site to check (default https://upzoneapp.fr/)
//   LIVE_CHECK_MEMBER_EMAIL / _PASSWORD a test personal account (fictitious person, profile completed)
//   LIVE_CHECK_PRO_EMAIL / _PASSWORD    a test professional account
//   LIVE_CHECK_EVENT_EMAIL / _PASSWORD  a test event account
// The passwords live in GitHub → Settings → Secrets and variables → Actions, never in this repository.
// The administration is only opened, never signed in to: an administrator password does not belong in an automatic check.
import { createRequire } from 'node:module';
import fs from 'node:fs';

const BASE = (process.env.LIVE_CHECK_URL || 'https://upzoneapp.fr/').replace(/\/?$/, '/');
const PUBLIC_PAGES = ['?landing=1', 'account.html', 'account.html?start=pro-kind', 'admin.html', 'demo.html', 'cgu.html', 'confidentialite.html', 'protection-des-mineurs.html', 'supprimer-mon-compte.html'];
const PUBLIC_FILES = ['manifest.webmanifest', 'sw.js', 'account.bundle.js', 'admin.bundle.js'];
// Buttons that only show another screen. Anything else is never touched.
const SAFE_ACTIONS = ['messages', 'people', 'talents'];
const ACCOUNTS = [['MEMBER', 'personal account'], ['PRO', 'professional account'], ['EVENT', 'event account']];

export async function loadPlaywright() {
  const require = createRequire(import.meta.url);
  try { return require('playwright'); } catch { return createRequire((process.env.LIVE_CHECK_PLAYWRIGHT || process.cwd()) + '/')('playwright'); }
}

// Collects what goes wrong on a page while it is used: script errors, files that do not load, server errors.
export function watch(page, problems, label) {
  const here = () => { try { return new URL(page.url()).pathname.split('/').pop() || '/'; } catch { return '?'; } };
  page.on('pageerror', (e) => problems.push(`${label} · ${here()} · script error: ${String(e.message || e).slice(0, 200)}`));
  page.on('requestfailed', (r) => { const why = r.failure()?.errorText || ''; if (!/ERR_ABORTED/.test(why)) problems.push(`${label} · ${here()} · did not load: ${r.url().split('?')[0].slice(0, 120)} (${why})`); });
  page.on('response', (r) => {
    const s = r.status(), u = r.url().split('?')[0];
    if (s >= 500) problems.push(`${label} · ${here()} · server error ${s}: ${u.slice(0, 120)}`);
    else if (s >= 400 && !page.expected?.(s, u)) problems.push(`${label} · ${here()} · refused ${s}: ${u.slice(0, 120)}`);
  });
}

export async function publicChecks(browser, devices, base, problems, notes) {
  for (const [name, options] of [['Android phone', devices['Pixel 7']], ['iPhone', devices['iPhone 14']], ['computer', {}]]) {
    const ctx = await browser.newContext(options);
    for (const path of PUBLIC_PAGES) {
      const page = await ctx.newPage();
      watch(page, problems, name);
      try {
        const r = await page.goto(base + path, { waitUntil: 'networkidle', timeout: 45000 });
        if (!r || r.status() !== 200) problems.push(`${name} · ${path} · answered ${r ? r.status() : 'nothing'}`);
        const text = await page.evaluate(() => document.body.innerText.trim().length);
        if (text < 100) problems.push(`${name} · ${path} · the page is almost empty (${text} characters)`);
      } catch (e) { problems.push(`${name} · ${path} · did not open: ${String(e.message).split('\n')[0].slice(0, 160)}`); }
      await page.close();
    }
    await ctx.close();
  }
  notes.push(`${PUBLIC_PAGES.length} public pages opened as an Android phone, an iPhone and a computer`);

  const ctx = await browser.newContext(devices['Pixel 7']);
  const seen = new Set(PUBLIC_FILES.map((f) => base + f));
  for (const path of PUBLIC_PAGES) {
    const page = await ctx.newPage();
    try {
      await page.goto(base + path, { waitUntil: 'networkidle', timeout: 45000 });
      for (const u of await page.evaluate(() => [...document.querySelectorAll('a[href],link[href],script[src],img[src]')].map((e) => e.href || e.src))) {
        if (u.startsWith(base)) seen.add(u.split('#')[0]);
      }
    } catch { /* already reported above */ }
    await page.close();
  }
  for (const u of seen) {
    const r = await ctx.request.get(u, { timeout: 30000 }).catch(() => null);
    if (!r || r.status() !== 200) problems.push(`link · ${u.replace(base, '/')} · answered ${r ? r.status() : 'nothing'}`);
  }
  notes.push(`${seen.size} links and files of the site answered`);

  // The sign-in screen: the « Connexion » tab leads to the e-mail field, and a wrong password gets a clear answer.
  const page = await ctx.newPage();
  page.expected = (s, u) => s === 400 && u.endsWith('/auth/v1/token');
  watch(page, problems, 'sign-in screen');
  try {
    await page.goto(base + 'account.html', { waitUntil: 'networkidle', timeout: 45000 });
    await page.locator('[data-mode="signin"]').first().click();
    await page.waitForTimeout(400);
    await page.locator('[data-mode="signin"]').first().click();
    await page.waitForTimeout(400);
    const focus = await page.evaluate(() => document.activeElement?.name || '');
    if (focus !== 'email') problems.push(`sign-in screen · « Connexion » does not lead to the e-mail field (cursor on « ${focus || 'nothing'} »)`);
    await page.fill('form[data-form="auth"] input[name="email"]', 'live-check-nobody@example.com');
    await page.fill('form[data-form="auth"] input[name="password"]', 'not-a-real-password-0');
    const [answer] = await Promise.all([
      page.waitForResponse((r) => r.url().includes('/auth/v1/token'), { timeout: 20000 }),
      page.locator('form[data-form="auth"] button[type="submit"]').click(),
    ]);
    await page.waitForTimeout(800);
    const said = (await page.locator('[role="alert"],.notice,.error').allTextContents()).join(' ').trim();
    if (answer.status() !== 400) problems.push(`sign-in screen · a wrong password was answered ${answer.status()} by the server (400 expected)`);
    if (!said) problems.push('sign-in screen · a wrong password shows no message');
    notes.push('sign-in screen: « Connexion » leads to the e-mail field, the server answers, a wrong password shows a message');
  } catch (e) { problems.push(`sign-in screen · ${String(e.message).split('\n')[0].slice(0, 160)}`); }
  await ctx.close();
}

const screenOf = (page) => page.evaluate(() => document.body.dataset.screen || '');
const targetsOf = (page) => page.evaluate((safe) => {
  const shown = (e) => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const out = new Set();
  for (const e of document.querySelectorAll('[data-view]')) if (shown(e)) out.add('[data-view="' + e.dataset.view + '"]');
  for (const a of safe) for (const e of document.querySelectorAll('[data-action="' + a + '"]')) if (shown(e)) out.add('[data-action="' + a + '"]');
  return [...out];
}, SAFE_ACTIONS);

// Signs in with a test account and opens every screen its buttons lead to (two steps deep), then signs out.
export async function accountChecks(browser, devices, base, account, label, problems, notes) {
  const ctx = await browser.newContext(devices['Pixel 7']);
  const page = await ctx.newPage();
  watch(page, problems, label);
  const visited = new Map();
  try {
    await page.goto(base + 'account.html', { waitUntil: 'networkidle', timeout: 45000 });
    // Twice: the first tap shows the sign-in screen, the second one opens the e-mail form.
    for (let i = 0; i < 2; i++) { await page.locator('[data-mode="signin"]').first().click(); await page.waitForTimeout(400); }
    await page.fill('form[data-form="auth"] input[name="email"]', account.email);
    await page.fill('form[data-form="auth"] input[name="password"]', account.password);
    await page.locator('form[data-form="auth"] button[type="submit"]').click();
    await page.waitForFunction(() => !['signin', 'signup', ''].includes(document.body.dataset.screen || ''), null, { timeout: 30000 }).catch(() => {});
    await page.waitForLoadState('networkidle').catch(() => {});
    const first = await screenOf(page);
    if (['signin', 'signup', ''].includes(first)) {
      const said = (await page.locator('[role="alert"],.notice,.error').allTextContents()).join(' ').trim();
      problems.push(`${label} · sign-in did not open the account${said ? ' (« ' + said.slice(0, 120) + ' »)' : ''}`);
      await ctx.close();
      return;
    }
    const open = async (path) => {
      await page.goto(base + 'account.html', { waitUntil: 'networkidle', timeout: 45000 });
      await page.waitForFunction(() => !!document.body.dataset.screen, null, { timeout: 15000 }).catch(() => {});
      for (const sel of path) {
        const el = page.locator(sel).first();
        if (!(await el.isVisible().catch(() => false))) return null;
        await el.click();
        await page.waitForTimeout(700);
        await page.waitForLoadState('networkidle').catch(() => {});
      }
      const screen = await screenOf(page);
      const text = await page.evaluate(() => (document.getElementById('account-root') || document.body).innerText.trim().length);
      if (text < 40) problems.push(`${label} · screen « ${screen || path.join(' › ')} » is almost empty`);
      return screen;
    };
    const queue = [[]];
    while (queue.length && visited.size < 25) {
      const path = queue.shift();
      const screen = await open(path);
      if (screen === null || visited.has(screen)) continue;
      visited.set(screen, path);
      if (path.length < 2) for (const t of await targetsOf(page)) queue.push([...path, t]);
    }
    notes.push(`${label}: signed in, ${visited.size} screens opened (${[...visited.keys()].join(', ')})`);
    // Sign out, so that no session of the check stays open.
    for (const path of visited.values()) {
      if (await open(path) === null) continue;
      const out = page.locator('[data-action="signout"]').first();
      if (await out.isVisible().catch(() => false)) { await out.click(); await page.waitForTimeout(1200); break; }
    }
  } catch (e) { problems.push(`${label} · ${String(e.message).split('\n')[0].slice(0, 160)}`); }
  await ctx.close();
}

export async function run(env = process.env) {
  const { chromium, devices } = await loadPlaywright();
  const browser = await chromium.launch();
  const problems = [], notes = [], skipped = [];
  await publicChecks(browser, devices, BASE, problems, notes);
  for (const [key, label] of ACCOUNTS) {
    const email = env[`LIVE_CHECK_${key}_EMAIL`], password = env[`LIVE_CHECK_${key}_PASSWORD`];
    if (email && password) await accountChecks(browser, devices, BASE, { email, password }, label, problems, notes);
    else skipped.push(label);
  }
  await browser.close();
  return { problems: [...new Set(problems)], notes, skipped };
}

if (import.meta.url === new URL(process.argv[1], 'file://').href) {
  const { problems, notes, skipped } = await run();
  const lines = [`# UPZONE live check — ${BASE}`, '', problems.length ? `**${problems.length} problem(s) found**` : '**Everything checked is working**', '',
    ...problems.map((p) => `- ❌ ${p}`), ...notes.map((n) => `- ✅ ${n}`),
    ...skipped.map((s) => `- ⏭️ ${s}: not checked (no test account given)`),
    '', 'Not covered by this check: the installed phone app, notifications arriving on a phone, scanning a QR code, sending messages, the administration behind its sign-in.'];
  console.log(lines.join('\n'));
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join('\n') + '\n');
  process.exit(problems.length ? 1 : 0);
}
