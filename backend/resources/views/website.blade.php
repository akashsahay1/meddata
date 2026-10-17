<!doctype html>
<html lang="en-IN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>MedikaBiz</title>
<meta name="claude:viewport-fit-sides" content="cover">
<meta name="description" content="Pharmacy inventory, expiry alerts, GST billing and reports for Indian medical shops. 7-day free trial, then ₹99 a month or ₹999 a year.">
<link rel="icon" href="/images/favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:wght@600;700;800&family=Figtree:wght@400;500;600;700&display=swap">
<style>
/* Layout: the brochure's rhythm, alternating navy and paper bands, each a centred 1120px column;
   the hero pairs the promise with a phone showing the real Home screen numbers. */
:root {
  --navy: #0B1730;
  --navy-2: #14244A;
  --navy-line: #24365F;
  --teal: #19BFAE;
  --teal-ink: #0A7D72;
  --paper: #F3F7FA;
  --card: #FFFFFF;
  --ink: #0B1730;
  --slate: #50617D;
  --mist: #B8C5D9;
  --line: #DCE5EE;
  --amber: #F2A33A;
  --coral: #E5626B;
  --blue: #4F86F7;
  --violet: #8B6CE3;
  --green: #2FB37A;
  --display: "Hanken Grotesk", "Segoe UI", system-ui, sans-serif;
  --body: "Figtree", "Segoe UI", system-ui, -apple-system, sans-serif;
  --wrap: 1120px;
  --radius: 22px;
  color-scheme: light;
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
body { margin: 0; background: var(--paper); color: var(--ink); font: 400 17px/1.6 var(--body); -webkit-font-smoothing: antialiased; }
h1, h2, h3 { font-family: var(--display); line-height: 1.12; margin: 0; text-wrap: balance; letter-spacing: -0.015em; }
h1 { font-size: clamp(2.3rem, 5.4vw, 3.9rem); font-weight: 800; }
h2 { font-size: clamp(1.8rem, 3.6vw, 2.6rem); font-weight: 800; }
h3 { font-size: 1.18rem; font-weight: 700; }
p { margin: 0; }
a { color: inherit; }
a:focus-visible, button:focus-visible, summary:focus-visible { outline: 3px solid var(--teal); outline-offset: 3px; border-radius: 8px; }

.band { padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); padding-block: clamp(56px, 8vw, 96px); }
.band.dark { background: var(--navy); color: #fff; }
.wrap { max-width: var(--wrap); margin: 0 auto; }
.eyebrow { font: 700 0.78rem/1 var(--display); letter-spacing: 0.12em; text-transform: uppercase; color: var(--teal-ink); }
.dark .eyebrow { color: var(--teal); }
.lede { color: var(--slate); font-size: 1.08rem; max-width: 62ch; }
.dark .lede { color: var(--mist); }
.head { display: grid; gap: 14px; margin-bottom: clamp(32px, 5vw, 48px); }

.btn { display: inline-flex; align-items: center; justify-content: center; gap: 10px; min-height: 52px; padding: 0 26px; border-radius: 14px; font: 700 1rem/1 var(--display); text-decoration: none; transition: transform .15s ease, background .15s ease; }
.btn:hover { transform: translateY(-1px); }
.btn-teal { background: var(--teal); color: var(--navy); }
.btn-teal:hover { background: #2AD0BF; }
.btn-ghost { border: 1.5px solid var(--navy-line); color: #fff; }
.btn-ghost:hover { border-color: var(--teal); }
@media (prefers-reduced-motion: reduce) { .btn { transition: none; } .btn:hover { transform: none; } }

/* Header + hero */
.top { display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; margin-bottom: clamp(40px, 7vw, 72px); }
.brand { font: 800 1.3rem/1 var(--display); letter-spacing: 0.08em; color: var(--teal); text-decoration: none; }
.nav { display: flex; gap: 6px 22px; flex-wrap: wrap; }
.nav a { color: var(--mist); text-decoration: none; font-weight: 600; font-size: 0.95rem; padding: 10px 0; }
.nav a:hover { color: #fff; }
.hero { position: relative; overflow: hidden; }
.hero::before, .hero::after { content: ""; position: absolute; border-radius: 50%; pointer-events: none; }
.hero::before { width: 520px; height: 520px; right: -150px; top: -170px; background: var(--navy-2); box-shadow: 0 0 0 80px #0F1E3E; }
.hero::after { width: 170px; height: 170px; right: 70px; top: 40px; background: var(--teal); opacity: .9; }
.hero .wrap { position: relative; z-index: 1; }
.hero-grid { display: grid; grid-template-columns: 1.15fr 0.85fr; gap: 48px; align-items: center; }
.hero-copy { display: grid; gap: 22px; min-width: 0; }
.hero-copy .lede { font-size: 1.2rem; color: #DCE6F3; }
.trial { justify-self: start; background: rgba(25, 191, 174, .16); color: var(--teal); border: 1px solid rgba(25, 191, 174, .45); font: 700 .78rem/1 var(--display); letter-spacing: .1em; text-transform: uppercase; padding: 9px 14px; border-radius: 999px; }
.price-line { font: 700 1.45rem/1.2 var(--display); }
.price-line span { color: var(--mist); font-weight: 600; font-size: 1rem; }
.ctas { display: flex; flex-wrap: wrap; gap: 12px; }
.platforms { color: var(--mist); font-size: .95rem; }

.phone { justify-self: center; width: min(300px, 100%); background: #0E1A33; border: 2px solid #2B3D63; border-radius: 40px; padding: 12px; box-shadow: 0 30px 60px rgba(0,0,0,.45); }
.screen { background: #F6F8FB; border-radius: 30px; overflow: hidden; color: var(--ink); }
.screen-bar { background: var(--navy-2); color: #fff; font: 700 1rem/1 var(--display); padding: 22px 18px 16px; }
.screen-body { padding: 16px; display: grid; gap: 12px; }
.screen-body small { color: var(--slate); font-weight: 600; font-size: .78rem; }
.tiles { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.tile { background: #fff; border-radius: 14px; padding: 12px; box-shadow: 0 2px 6px rgba(11,23,48,.08); display: grid; gap: 4px; }
.tile b { font: 800 1.35rem/1 var(--display); font-variant-numeric: tabular-nums; }
.tile .v-teal { color: var(--teal-ink); }
.tile .v-amber { color: #B86A00; }
.watch { background: #DDF6F2; border-radius: 14px; padding: 12px; font-weight: 700; font-size: .85rem; }
.quick { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
.quick div { background: #fff; border-radius: 12px; padding: 10px 4px; text-align: center; font-size: .72rem; font-weight: 700; box-shadow: 0 2px 6px rgba(11,23,48,.08); display: grid; gap: 4px; justify-items: center; }
.quick svg { width: 18px; height: 18px; stroke: var(--teal-ink); }
.preview-note { text-align: center; color: var(--slate); font-size: .7rem; font-weight: 600; padding-bottom: 6px; }

.promise { margin-top: clamp(48px, 7vw, 80px); background: var(--navy-2); border: 1px solid var(--navy-line); border-radius: var(--radius); padding: 26px 28px; display: grid; grid-template-columns: auto 1fr; gap: 10px 28px; align-items: baseline; }
.promise p { font: 700 clamp(1.15rem, 2.4vw, 1.5rem)/1.35 var(--display); }

/* Problems */
.trio { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
.problem { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); padding: 26px; display: grid; gap: 10px; align-content: start; min-width: 0; }
.problem p { color: var(--slate); }
.dot { width: 12px; height: 12px; border-radius: 50%; }
.answer { margin-top: 28px; display: flex; flex-wrap: wrap; gap: 8px 18px; align-items: baseline; }
.answer strong { font: 800 clamp(1.1rem, 2.4vw, 1.45rem)/1.3 var(--display); }

/* Features */
.features { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
.feature { background: var(--navy-2); border: 1px solid var(--navy-line); border-radius: var(--radius); padding: 24px; display: grid; gap: 10px; align-content: start; min-width: 0; }
.feature p { color: var(--mist); font-size: .98rem; }
.feature .icon { width: 44px; height: 44px; border-radius: 12px; display: grid; place-items: center; }
.feature .icon svg { width: 22px; height: 22px; stroke: var(--navy); fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
.feature.wide { grid-column: span 3; grid-template-columns: auto 1fr auto; align-items: center; gap: 18px 22px; background: linear-gradient(120deg, #123B4A, var(--navy-2) 60%); border-color: #1F5C66; }
.feature.wide p { max-width: 70ch; }
.new { justify-self: start; font: 700 .72rem/1 var(--display); letter-spacing: .1em; text-transform: uppercase; color: var(--navy); background: var(--teal); padding: 7px 10px; border-radius: 999px; }
.fine { color: var(--mist); font-size: .85rem; margin-top: 18px; }

/* Day */
.day { display: grid; grid-template-columns: repeat(5, 1fr); gap: 14px; counter-reset: step; }
.step { background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 20px; display: grid; gap: 8px; align-content: start; min-width: 0; }
.step .when { font: 800 .8rem/1 var(--display); letter-spacing: .1em; text-transform: uppercase; color: var(--teal-ink); }
.step .when::before { counter-increment: step; content: counter(step) "  "; color: var(--slate); }
.step p { color: var(--slate); font-size: .95rem; }

/* Pricing */
.plans { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; align-items: stretch; }
.plan { border-radius: var(--radius); padding: 30px 26px; display: grid; gap: 12px; align-content: start; text-align: center; min-width: 0; }
.plan.trialcard { background: var(--navy-2); border: 1px solid var(--navy-line); }
.plan.paid { background: #fff; color: var(--ink); }
.plan.best { box-shadow: 0 0 0 3px var(--teal); }
.plan .name { font: 700 .82rem/1 var(--display); letter-spacing: .12em; text-transform: uppercase; color: var(--slate); }
.plan.trialcard .name { color: var(--teal); }
.plan .amount { font: 800 3rem/1 var(--display); font-variant-numeric: tabular-nums; }
.plan .per { color: var(--slate); font-weight: 600; }
.plan.trialcard .per { color: var(--mist); }
.plan .save { color: var(--teal-ink); font-weight: 700; }
.badge { justify-self: center; background: var(--teal); color: var(--navy); font: 700 .72rem/1 var(--display); letter-spacing: .1em; text-transform: uppercase; padding: 7px 10px; border-radius: 999px; }
.devices { margin-top: 28px; display: flex; flex-wrap: wrap; gap: 10px 26px; color: var(--mist); }
.devices b { color: #fff; }

/* Mission */
.mission { display: grid; grid-template-columns: auto 1fr 1fr; gap: 28px 40px; align-items: center; }
.heart { width: 132px; height: 132px; border-radius: 50%; background: #D8F5F0; display: grid; place-items: center; }
.heart svg { width: 60px; height: 60px; fill: var(--teal); }
.mission h3 { font-size: 1.35rem; }
.mission .who { font: 700 .78rem/1 var(--display); letter-spacing: .12em; text-transform: uppercase; color: var(--teal-ink); margin-bottom: 10px; }
.motto { margin-top: 32px; background: var(--navy); color: #fff; border-radius: var(--radius); padding: 24px; text-align: center; font: 700 clamp(1.05rem, 2.2vw, 1.3rem)/1.35 var(--display); }

/* FAQ */
.faq { display: grid; grid-template-columns: 1fr 1fr; gap: 12px 18px; }
.faq details { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 4px 20px; }
.faq summary { cursor: pointer; font: 700 1.05rem/1.4 var(--display); padding: 16px 0; list-style: none; display: flex; justify-content: space-between; gap: 12px; }
.faq summary::-webkit-details-marker { display: none; }
.faq summary::after { content: "+"; color: var(--teal-ink); font-size: 1.3rem; line-height: 1; }
.faq details[open] summary::after { content: "–"; }
.faq details p { color: var(--slate); padding-bottom: 18px; }

/* Closing */
.closing { display: grid; grid-template-columns: 1fr auto; gap: 28px; align-items: center; }
.contact { display: grid; gap: 6px; color: var(--mist); }
.contact .num { color: #fff; font: 700 1.25rem/1.2 var(--display); user-select: all; }
footer { border-top: 1px solid var(--navy-line); margin-top: 56px; padding-top: 24px; display: flex; flex-wrap: wrap; justify-content: space-between; gap: 10px 24px; color: var(--mist); font-size: .88rem; }

@media (max-width: 900px) {
  .hero-grid, .closing { grid-template-columns: 1fr; }
  .features, .trio, .plans { grid-template-columns: 1fr 1fr; }
  .feature.wide { grid-column: span 2; grid-template-columns: auto 1fr; }
  .feature.wide .btn { grid-column: 1 / -1; justify-self: start; }
  .day { grid-template-columns: 1fr 1fr; }
  .mission { grid-template-columns: 1fr; }
  .faq { grid-template-columns: 1fr; }
  .hero::after { right: -40px; top: -40px; }
}
@media (max-width: 600px) {
  .features, .trio, .plans, .day { grid-template-columns: 1fr; }
  .feature.wide { grid-column: auto; grid-template-columns: 1fr; }
  .promise { grid-template-columns: 1fr; }
  .hero::before { width: 360px; height: 360px; right: -200px; top: -200px; box-shadow: 0 0 0 50px #0F1E3E; }
  .hero::after { width: 110px; height: 110px; right: -30px; top: -30px; }
}
</style>
</head>
<body>

<section class="band dark hero">
  <div class="wrap">
    <header class="top">
      <a class="brand" href="#">MEDIKABIZ</a>
      <nav class="nav" aria-label="Sections">
        <a href="#features">Features</a>
        <a href="#pricing">Pricing</a>
        <a href="#faq">Questions</a>
        <a href="#contact">Contact</a>
      </nav>
    </header>
    <div class="hero-grid">
      <div class="hero-copy">
        <span class="trial">7-day free trial</span>
        <h1>The smarter way to manage your pharmacy.</h1>
        <p class="lede">Stock visibility. Expiry alerts. GST billing. Business reports. One app for the counter and the back office.</p>
        <p class="price-line">₹99<span>/month</span> &nbsp;·&nbsp; ₹999<span>/year</span></p>
        <div class="ctas">
          <a class="btn btn-teal" href="#contact">Start free for 7 days</a>
          <a class="btn btn-ghost" href="#features">See what it does</a>
        </div>
        <p class="platforms">Android phone · Windows computer · Mac</p>
      </div>
      <div class="phone" role="img" aria-label="MedikaBiz home screen: stock value ₹2.4 lakh, 8 medicines low on stock, 12 expiring soon, and quick actions">
        <div class="screen">
          <div class="screen-bar">MedikaBiz</div>
          <div class="screen-body">
            <small>Pharmacy overview</small>
            <div class="tiles">
              <div class="tile"><small>Stock value</small><b class="v-teal">₹2.4L</b></div>
              <div class="tile"><small>Low stock</small><b class="v-amber">08</b></div>
            </div>
            <div class="watch">Expiry watch · 12 items</div>
            <small>QUICK ACTIONS</small>
            <div class="quick">
              <div><svg viewBox="0 0 24 24" fill="none" stroke-width="2.2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>New bill</div>
              <div><svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linejoin="round"><rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/></svg>Stock</div>
              <div><svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 18l6-6 4 4 6-7"/><path d="M15 9h5v5"/></svg>Reports</div>
            </div>
            <p class="preview-note">Illustrative preview</p>
          </div>
        </div>
      </div>
    </div>
    <div class="promise">
      <span class="eyebrow">The promise</span>
      <p>Know your stock. Act on alerts. Keep bills and business reports within reach.</p>
    </div>
  </div>
</section>

<section class="band" aria-labelledby="why">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">Why it matters</span>
      <h2 id="why">Everyday pharmacy work deserves better visibility.</h2>
      <p class="lede">MedikaBiz helps owners run routine work the same way every day, instead of relying on memory, registers and scattered slips.</p>
    </div>
    <div class="trio">
      <div class="problem"><span class="dot" style="background: var(--amber)"></span><h3>When stock is hard to track</h3><p>Manual checks make it hard to know what is on the shelf and what needs to be ordered again.</p></div>
      <div class="problem"><span class="dot" style="background: var(--coral)"></span><h3>When expiry is easy to miss</h3><p>A warning window you set brings medicines that are expiring soon, or already expired, to your attention.</p></div>
      <div class="problem"><span class="dot" style="background: var(--blue)"></span><h3>When balances are unclear</h3><p>Bill history and unpaid balances show who owes what, so payment follow-up doesn't depend on a notebook.</p></div>
    </div>
    <p class="answer"><span class="eyebrow">MedikaBiz answer</span><strong>A dashboard, filters, alerts, billing and reports in one place.</strong></p>
  </div>
</section>

<section class="band dark" id="features" aria-labelledby="feat">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">Features</span>
      <h2 id="feat">Everything a medical shop does in a day</h2>
      <p class="lede">From opening the shop to closing the books, each task has its own place in the app.</p>
    </div>
    <div class="features">
      <article class="feature">
        <div class="icon" style="background: var(--teal)"><svg viewBox="0 0 24 24"><path d="M3 12h4l3-8 4 16 3-8h4"/></svg></div>
        <h3>Your shop at a glance</h3>
        <p>Home shows stock value, low-stock and expiring medicines, a "Needs attention" list and quick actions for new bills, stock and reports.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--amber)"><svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M9 4v16"/></svg></div>
        <h3>Inventory you can trust</h3>
        <p>Filter by low stock, expiring soon and expired. Strips and loose tablets are counted properly, batch by batch.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--coral)"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg></div>
        <h3>Low-stock and expiry alerts</h3>
        <p>Choose your own low-stock level, such as 5, 10 or 15, and an expiry warning of up to 90 days. A daily reminder at the time you pick.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--blue)"><svg viewBox="0 0 24 24"><path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/></svg></div>
        <h3>GST bills in seconds</h3>
        <p>Make a bill, take full or part payment, and print it on A4 or an 80 mm receipt printer. Find any bill by date, customer name or phone number.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--green)"><svg viewBox="0 0 24 24"><path d="M4 12l5 5L20 6"/></svg></div>
        <h3>Payment follow-up</h3>
        <p>See unpaid bills and the balance on each, record money received, and send the bill or balance on WhatsApp or email.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--violet)"><svg viewBox="0 0 24 24"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg></div>
        <h3>Reports and GST data</h3>
        <p>Stock value, purchases, profit and loss, and GST-ready summaries for your returns. Check figures with your accountant before filing.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--teal)"><svg viewBox="0 0 24 24"><path d="M12 3v12M7 10l5 5 5-5"/><path d="M4 21h16"/></svg></div>
        <h3>Bring your stock in</h3>
        <p>Import your existing stock from Excel or CSV, export it to Excel, and keep a backup you can restore.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--amber)"><svg viewBox="0 0 24 24"><path d="M9 3h6l1 4H8z"/><rect x="4" y="7" width="16" height="14" rx="2"/><path d="M12 11v6M9 14h6"/></svg></div>
        <h3>Edit, cancel or return</h3>
        <p>Correct a bill and keep its invoice number, cancel it, or take back a returned item with a credit note.</p>
      </article>
      <article class="feature">
        <div class="icon" style="background: var(--blue)"><svg viewBox="0 0 24 24"><rect x="3" y="4" width="13" height="10" rx="1.5"/><rect x="14" y="9" width="7" height="12" rx="1.5"/><path d="M7 18h5"/></svg></div>
        <h3>Phone and computer together</h3>
        <p>Use it on an Android phone at the shelf and a Windows computer at the counter. Every device of the shop stays in sync.</p>
      </article>
      <article class="feature wide">
        <div class="icon" style="background: var(--teal)"><svg viewBox="0 0 24 24"><path d="M4 7V4h3M17 4h3v3M20 17v3h-3M7 20H4v-3"/><path d="M8 9h8M8 12h8M8 15h5"/></svg></div>
        <div style="display: grid; gap: 8px; min-width: 0">
          <span class="new">New</span>
          <h3>Add stock from supplier bills</h3>
          <p>Photograph your supplier's bills or pick their PDFs, as many as you have. MedikaBiz reads the medicines, batches, expiry dates and rates. You check each item, and only then is it added to stock.</p>
        </div>
      </article>
    </div>
  </div>
</section>

<section class="band" aria-labelledby="dayh">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">A day with MedikaBiz</span>
      <h2 id="dayh">From opening to closing</h2>
    </div>
    <div class="day">
      <div class="step"><span class="when">Open</span><h3>Check Home</h3><p>See stock value, low stock and expiring medicines.</p></div>
      <div class="step"><span class="when">Restock</span><h3>Plan purchases</h3><p>Filter low-stock items and add supplier bills.</p></div>
      <div class="step"><span class="when">Sell</span><h3>Make bills</h3><p>Bill the customer, then print or share the invoice.</p></div>
      <div class="step"><span class="when">Follow up</span><h3>Collect dues</h3><p>Check unpaid bills and record payments received.</p></div>
      <div class="step"><span class="when">Review</span><h3>Read reports</h3><p>Look at stock, purchases and profit for the day or month.</p></div>
    </div>
  </div>
</section>

<section class="band dark" id="pricing" aria-labelledby="price">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">Pricing</span>
      <h2 id="price">Try MedikaBiz free for 7 days</h2>
      <p class="lede">Use the whole app first, then choose monthly or yearly.</p>
    </div>
    <div class="plans">
      <div class="plan trialcard">
        <span class="name">Free trial</span>
        <span class="amount">₹0</span>
        <span class="per">7 days, every feature</span>
        <a class="btn btn-teal" href="#contact">Start free</a>
      </div>
      <div class="plan paid">
        <span class="name">Monthly</span>
        <span class="amount">₹99</span>
        <span class="per">per month</span>
      </div>
      <div class="plan paid best">
        <span class="badge">Best value</span>
        <span class="name">Yearly</span>
        <span class="amount">₹999</span>
        <span class="per">per year</span>
        <span class="save">Save ₹189 compared with 12 monthly payments</span>
      </div>
    </div>
    <div class="devices"><span><b>Android</b> phone</span><span><b>Windows</b> computer</span><span><b>Mac</b></span><span>One account for all your shop's devices</span></div>
  </div>
</section>

<section class="band" aria-labelledby="missionh">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">Purpose-led</span>
      <h2 id="missionh">Useful technology with a social mission</h2>
      <p class="lede">MedikaBiz operates under Yatharthvadi Foundation, a Section 8 company.</p>
    </div>
    <div class="mission">
      <div class="heart" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 21s-7.5-4.6-9.6-9.2C.9 8.5 2.9 4.5 6.6 4.5c2.1 0 3.6 1.1 5.4 3 1.8-1.9 3.3-3 5.4-3 3.7 0 5.7 4 4.2 7.3C19.5 16.4 12 21 12 21z"/></svg></div>
      <div><p class="who">MedikaBiz</p><h3>Practical tools for pharmacy owners.</h3></div>
      <div><p class="who">Yatharthvadi Foundation</p><h3>A portion of subscription profits is intended to support social work.</h3></div>
    </div>
    <p class="motto">Subscribe for the software. Support a wider purpose.</p>
  </div>
</section>

<section class="band" id="faq" aria-labelledby="faqh" style="padding-top: 0">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">Questions</span>
      <h2 id="faqh">What pharmacy owners ask</h2>
    </div>
    <div class="faq">
      <details><summary>How can I try it?</summary><p>Start the 7-day free trial. Every feature is open during the trial.</p></details>
      <details><summary>What does it cost?</summary><p>₹99 a month, or ₹999 a year, which saves ₹189.</p></details>
      <details><summary>Which devices does it run on?</summary><p>Android phones, Windows computers and Macs. All devices of your shop share the same stock and bills.</p></details>
      <details><summary>Can I bring in my existing stock?</summary><p>Yes. Import it from an Excel or CSV file, or add supplier bills from a photo or PDF.</p></details>
      <details><summary>Can I track customer balances?</summary><p>Yes. Bills can be part paid; unpaid balances are listed, and you record each payment as it comes in.</p></details>
      <details><summary>Does it file my GST returns?</summary><p>It prepares GST-ready summaries of your sales and purchases. Check the figures with your accountant before filing.</p></details>
    </div>
  </div>
</section>

<section class="band dark" id="contact" aria-labelledby="ctah">
  <div class="wrap">
    <div class="closing">
      <div class="head" style="margin: 0">
        <span class="eyebrow">Get started</span>
        <h2 id="ctah">Bring more clarity to your pharmacy.</h2>
        <p class="lede">Message us on WhatsApp. We'll send the app for your phone or computer and help you set up your shop.</p>
      </div>
      <div class="contact">
        <a class="btn btn-teal" href="https://wa.me/917053792466?text=Hello%2C%20I%20want%20to%20try%20MedikaBiz">Message us on WhatsApp</a>
        <span>or call or WhatsApp</span>
        <span class="num">+91 70537 92466</span>
      </div>
    </div>
    <footer>
      <span>MedikaBiz · Pharmacy management, made simpler</span>
      <span>A Yatharthvadi Foundation initiative</span>
    </footer>
  </div>
</section>

</body>
</html>
