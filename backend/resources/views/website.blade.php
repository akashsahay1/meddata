<!doctype html>
<html lang="en-IN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Medikabiz</title>
<meta name="claude:viewport-fit-sides" content="cover">
<meta name="description" content="Pharmacy inventory, expiry alerts, GST billing and reports for Indian medical shops. 7-day free trial, then ₹99 a month or ₹999 a year.">
<link rel="icon" href="/images/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/images/apple-touch-icon.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Medikabiz">
<meta property="og:title" content="Medikabiz: the smarter way to manage your pharmacy">
<meta property="og:description" content="Stock, expiry alerts, GST billing and reports for medical shops. 7-day free trial, then ₹99 a month or ₹999 a year.">
<meta property="og:url" content="{{ url('/') }}">
<meta property="og:image" content="{{ asset('images/og-medikabiz.png') }}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Medikabiz logo: Stock, Billing, Invoicing">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="{{ asset('images/og-medikabiz.png') }}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:wght@600;700;800&family=Figtree:wght@400;500;600;700&display=swap">
<style>
/* Layout: the brochure's rhythm, alternating navy and paper bands, each a centred 1120px column;
   the hero pairs the promise with a phone showing the real Home screen numbers. */
:root {
  --navy: #071D3B;
  --navy-2: #0E2A52;
  --navy-line: #1E3B66;
  --head: #0A2448;
  --teal: #00B88D;
  --teal-ink: #00785C;
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
.btn-teal:hover { background: #1FCB9F; }
.btn-ghost { border: 1.5px solid var(--navy-line); color: #fff; }
.btn-ghost:hover { border-color: var(--teal); }
@media (prefers-reduced-motion: reduce) { .btn { transition: none; } .btn:hover { transform: none; } }

/* Header + hero */
.site-head { background: var(--head); border-bottom: 1px solid var(--navy-line); padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); position: sticky; top: env(safe-area-inset-top, 0px); z-index: 20; }
body::before { content: ""; position: fixed; inset: 0 0 auto; height: env(safe-area-inset-top, 0px); z-index: 21; background: var(--head); }
.head-row { display: flex; align-items: center; justify-content: space-between; gap: 12px 24px; flex-wrap: wrap; padding-block: 12px; }
.brand { display: block; line-height: 0; }
.brand img { height: 40px; width: auto; }
.nav { display: flex; align-items: center; gap: 4px 22px; flex-wrap: wrap; }
.nav a:not(.btn) { color: var(--mist); text-decoration: none; font-weight: 600; font-size: .95rem; padding: 12px 0; }
.nav a:not(.btn):hover { color: #fff; }
.btn-sm { min-height: 44px; padding: 0 18px; font-size: .92rem; border-radius: 12px; }
.get { display: flex; flex-wrap: wrap; gap: 10px; }
.store { display: inline-flex; align-items: center; gap: 10px; min-height: 52px; padding: 6px 16px 6px 12px; border-radius: 12px; background: #000; border: 1px solid #3A4B6E; color: #fff; text-decoration: none; font: 700 1.05rem/1.1 var(--display); }
.store:hover { border-color: var(--teal); }
.store svg { width: 26px; height: 26px; fill: currentColor; flex: none; }
.store span { display: grid; }
.store small { font: 500 .7rem/1.2 var(--body); color: #C9D3E3; }
.hero { position: relative; overflow: hidden; }
.hero::before, .hero::after { content: ""; position: absolute; border-radius: 50%; pointer-events: none; }
.hero::before { width: 520px; height: 520px; right: -150px; top: -170px; background: var(--navy-2); box-shadow: 0 0 0 80px #0A2347; }
.hero::after { width: 170px; height: 170px; right: 70px; top: 40px; background: var(--teal); opacity: .9; }
.hero .wrap { position: relative; z-index: 1; }
.hero-grid { display: grid; grid-template-columns: 0.9fr 1.1fr; gap: 56px; align-items: center; }
.hero-copy { display: grid; gap: 22px; min-width: 0; }
.hero-copy .lede { font-size: 1.2rem; color: #DCE6F3; }
.trial { justify-self: start; background: rgba(0, 184, 141, .16); color: var(--teal); border: 1px solid rgba(0, 184, 141, .45); font: 700 .78rem/1 var(--display); letter-spacing: .1em; text-transform: uppercase; padding: 9px 14px; border-radius: 999px; }
.price-line { font: 700 1.45rem/1.2 var(--display); }
.price-line span { color: var(--mist); font-weight: 600; font-size: 1rem; }
.ctas { display: flex; flex-wrap: wrap; gap: 12px; }

.shots { position: relative; margin: 0 0 0 4%; min-width: 0; }
.shots .desk { box-shadow: 0 30px 70px rgba(0, 0, 0, .45); }
.shots .hand { position: absolute; width: 28%; left: -10%; bottom: -14%; }

/* Device frames around the real screenshots */
.window { border-radius: 12px; overflow: hidden; border: 1px solid #C9D4DF; background: #fff; box-shadow: 0 16px 40px rgba(7, 29, 59, .14); }
.window .bar { display: flex; align-items: center; justify-content: space-between; height: 32px; padding: 0 4px 0 12px; background: #E8EDF2; border-bottom: 1px solid #D6DEE6; color: #33435C; font: 600 .78rem/1 var(--body); }
.window .bar-title { display: flex; align-items: center; gap: 8px; }
.window .bar-ctl { display: flex; }
.window .bar-ctl i { font-style: normal; width: 40px; text-align: center; color: #50617D; font-size: .8rem; }
.window > img { display: block; width: 100%; height: auto; }
.device { container-type: inline-size; }
.device .frame { position: relative; padding: 2.8cqw; border-radius: 14cqw; background: linear-gradient(150deg, #2E3238, #0C0E11 60%); box-shadow: inset 0 0 0 .6cqw #464A52, inset 0 0 0 1.4cqw #15171B, 0 28px 60px rgba(4, 12, 28, .45); }
.device .frame::before, .device .frame::after { content: ""; position: absolute; right: -1.1cqw; width: 1.2cqw; border-radius: 0 1cqw 1cqw 0; background: linear-gradient(90deg, #15171B, #3A3E45); }
.device .frame::before { top: 20%; height: 7%; }
.device .frame::after { top: 31%; height: 14%; }
.device .screen { position: relative; overflow: hidden; border-radius: 11.4cqw; background: #000; }
.device .screen img { display: block; width: 100%; height: auto; }
.device .camera { position: absolute; z-index: 2; top: 2.6cqw; left: 50%; width: 3.8cqw; height: 3.8cqw; transform: translateX(-50%); border-radius: 50%; background: #050608; box-shadow: 0 0 0 .5cqw #1A1C21; }
.device .status { position: absolute; z-index: 1; inset: 0 0 auto; height: 9.2cqw; display: flex; align-items: center; justify-content: space-between; padding: .6cqw 7cqw 0; font: 600 3.7cqw/1 -apple-system, "Segoe UI", Roboto, sans-serif; }
.device .status.light { color: #fff; }
.device .status.dark { color: #0A302E; }
.device .sicons { display: flex; align-items: center; gap: 1.6cqw; }
.device .sicons svg { height: 3.1cqw; width: auto; fill: currentColor; }

.promise { margin-top: clamp(48px, 7vw, 80px); background: var(--navy-2); border: 1px solid var(--navy-line); border-radius: var(--radius); padding: 26px 28px; display: grid; grid-template-columns: auto 1fr; gap: 10px 28px; align-items: baseline; }
.promise p { font: 700 clamp(1.15rem, 2.4vw, 1.5rem)/1.35 var(--display); }

/* Problems */
.trio { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
.problem { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); padding: 26px; display: grid; gap: 10px; align-content: start; min-width: 0; }
.problem p { color: var(--slate); }
.dot { width: 12px; height: 12px; border-radius: 50%; }
.answer { margin-top: 28px; display: flex; flex-wrap: wrap; gap: 8px 18px; align-items: baseline; }
.answer strong { font: 800 clamp(1.1rem, 2.4vw, 1.45rem)/1.3 var(--display); }

/* Screens */
.gallery { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; align-items: start; }
.gallery figure { margin: 0; display: grid; gap: 12px; min-width: 0; }
.gallery figcaption { color: var(--slate); font-size: .95rem; }
.gallery figcaption b { color: var(--ink); font-family: var(--display); display: block; font-size: 1.05rem; }
.gallery .wide { grid-column: 1 / -1; display: grid; grid-template-columns: 1.6fr 1fr; gap: 24px; align-items: center; }

/* Features */
.features { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
.feature { background: var(--navy-2); border: 1px solid var(--navy-line); border-radius: var(--radius); padding: 24px; display: grid; gap: 10px; align-content: start; min-width: 0; }
.feature p { color: var(--mist); font-size: .98rem; }
.feature .icon { width: 44px; height: 44px; border-radius: 12px; display: grid; place-items: center; }
.feature .icon svg { width: 22px; height: 22px; stroke: var(--navy); fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
.feature.wide { grid-column: span 3; grid-template-columns: auto 1fr auto; align-items: center; gap: 18px 22px; background: linear-gradient(120deg, #0B3F4C, var(--navy-2) 60%); border-color: #17606A; }
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
.plans { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; align-items: stretch; }
.plan { position: relative; border-radius: var(--radius); padding: 32px 28px; display: grid; grid-template-rows: subgrid; grid-row: span 3; gap: 24px; min-width: 0; }
.plan.trialcard { background: var(--navy-2); border: 1px solid var(--navy-line); }
.plan.paid { background: #fff; color: var(--ink); }
.plan.best { box-shadow: 0 0 0 3px var(--teal), 0 24px 60px rgba(0, 0, 0, .35); }
.plan-top { display: grid; gap: 6px; }
.plan .name { font: 700 .82rem/1 var(--display); letter-spacing: .12em; text-transform: uppercase; color: var(--slate); }
.plan.trialcard .name { color: var(--teal); }
.plan .amount { font: 800 3.4rem/1 var(--display); font-variant-numeric: tabular-nums; margin-top: 10px; }
.plan .per { color: var(--slate); font-weight: 600; }
.plan.trialcard .per, .plan.trialcard .note { color: var(--mist); }
.plan .note { color: var(--slate); font-size: .95rem; margin-top: 8px; }
.plan .note b { color: var(--teal-ink); }
.plan .btn { width: 100%; }
.btn-navy { background: var(--navy); color: #fff; }
.btn-navy:hover { background: var(--navy-2); }
.includes { list-style: none; margin: 0; padding: 22px 0 0; border-top: 1px solid var(--line); display: grid; gap: 12px; font-size: .96rem; }
.trialcard .includes { border-color: var(--navy-line); color: #DCE6F3; }
.includes li { display: grid; grid-template-columns: 22px 1fr; gap: 10px; align-items: start; }
.includes svg { width: 22px; height: 22px; fill: none; stroke: var(--teal-ink); stroke-width: 2.4; stroke-linecap: round; stroke-linejoin: round; }
.trialcard .includes svg { stroke: var(--teal); }
.badge { position: absolute; top: -14px; left: 28px; background: var(--teal); color: var(--navy); font: 700 .72rem/1 var(--display); letter-spacing: .1em; text-transform: uppercase; padding: 8px 12px; border-radius: 999px; }
.devices { margin-top: 28px; display: flex; flex-wrap: wrap; gap: 10px 26px; color: var(--mist); }
.devices b { color: #fff; }

/* Download */
.downloads { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
.dl { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); padding: 28px; display: grid; grid-template-rows: subgrid; grid-row: span 5; gap: 12px; min-width: 0; }
.dl-icon { width: 56px; height: 56px; border-radius: 16px; background: var(--navy); display: grid; place-items: center; }
.dl-icon svg { width: 30px; height: 30px; fill: #fff; }
.dl .req { color: var(--slate); font-weight: 600; font-size: .95rem; }
.dl .btn { width: 100%; }
.dl .tip { color: var(--slate); font-size: .92rem; }
.dl .tip b { color: var(--ink); }
.dl-help { margin-top: 24px; color: var(--slate); }
.dl-help b { color: var(--ink); user-select: all; }

/* Mission */
.mission { display: grid; grid-template-columns: auto 1fr 1fr; gap: 28px 40px; align-items: center; }
.heart { width: 132px; height: 132px; border-radius: 50%; background: #D5F5EC; display: grid; place-items: center; }
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
  .nav a:not(.btn) { display: none; }
  .features, .trio { grid-template-columns: 1fr 1fr; }
  .plans, .downloads { grid-template-columns: 1fr; max-width: 520px; margin: 0 auto; }
  .feature.wide { grid-column: span 2; grid-template-columns: auto 1fr; }
  .feature.wide .btn { grid-column: 1 / -1; justify-self: start; }
  .day { grid-template-columns: 1fr 1fr; }
  .mission { grid-template-columns: 1fr; }
  .gallery { grid-template-columns: 1fr 1fr; }
  .gallery .wide { grid-template-columns: 1fr; }
  .shots { margin: 24px 0 40px 9%; }
  .faq { grid-template-columns: 1fr; }
  .hero::after { right: -40px; top: -40px; }
}
@media (max-width: 600px) {
  .features, .trio, .plans, .day { grid-template-columns: 1fr; }
  .feature.wide { grid-column: auto; grid-template-columns: 1fr; }
  .promise { grid-template-columns: 1fr; }
  .gallery { grid-template-columns: 1fr; }
  .gallery .tall { max-width: 300px; width: 100%; justify-self: center; }
  .hero::before { width: 360px; height: 360px; right: -200px; top: -200px; box-shadow: 0 0 0 50px #0A2347; }
  .hero::after { width: 110px; height: 110px; right: -30px; top: -30px; }
}
</style>
</head>
<body>

<header class="site-head">
  <div class="wrap head-row">
    <a class="brand" href="#"><img src="/images/medikabiz_logo_web.png" alt="Medikabiz" width="168" height="44"></a>
    <nav class="nav" aria-label="Sections">
      <a href="#features">Features</a>
      <a href="#pricing">Pricing</a>
      <a href="#download">Download</a>
      <a href="#faq">Questions</a>
      <a class="btn btn-teal btn-sm" href="#contact">Start free trial</a>
    </nav>
  </div>
</header>

<section class="band dark hero">
  <div class="wrap">
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
        <div class="get" aria-label="Download the app">
          <a class="store" href="/downloads/Medikabiz.apk"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 9.5h10V17a1 1 0 0 1-1 1h-1v2.5a1 1 0 0 1-2 0V18h-2v2.5a1 1 0 0 1-2 0V18H8a1 1 0 0 1-1-1zM5 10a1 1 0 0 1 2 0v5a1 1 0 0 1-2 0zm12 0a1 1 0 0 1 2 0v5a1 1 0 0 1-2 0zM7.2 8.5a4.8 4.8 0 0 1 2.3-3.6L8.6 3.4a.4.4 0 0 1 .7-.4l.9 1.5a5 5 0 0 1 3.6 0l.9-1.5a.4.4 0 0 1 .7.4l-.9 1.5a4.8 4.8 0 0 1 2.3 3.6zM10 6.6a.7.7 0 1 0 0 1.4.7.7 0 0 0 0-1.4zm4 0a.7.7 0 1 0 0 1.4.7.7 0 0 0 0-1.4z"/></svg><span><small>Download for</small>Android</span></a>
          <a class="store" href="/downloads/Medikabiz-Setup.exe"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 5.3l7.4-1v7.2H3zm8.4-1.2L21 2.8v8.7h-9.6zM3 12.5h7.4v7.2L3 18.7zm8.4 0H21v8.7l-9.6-1.3z"/></svg><span><small>Download for</small>Windows</span></a>
          <a class="store" href="/downloads/Medikabiz.dmg"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7a4.5 4.5 0 0 0-3.5-1.9c-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8A4.7 4.7 0 0 0 4.2 9.5c-1.7 2.9-.4 7.3 1.2 9.7.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4a10 10 0 0 0 1.3-2.8 4.3 4.3 0 0 1-2.7-3.8zM14 5.5a4.3 4.3 0 0 0 1-3.1 4.4 4.4 0 0 0-2.9 1.5 4.1 4.1 0 0 0-1 3 3.7 3.7 0 0 0 2.9-1.4z"/></svg><span><small>Download for</small>Mac</span></a>
        </div>
      </div>
      <figure class="shots">
        <div class="window desk"><div class="bar"><span class="bar-title"><img src="/images/favicon.svg" alt="" width="14" height="14">Medikabiz</span><span class="bar-ctl" aria-hidden="true"><i>–</i><i>▢</i><i>✕</i></span></div><img src="/images/screens/desktop-home.webp" width="1600" height="1000" alt="Medikabiz on a computer: stock value, medicines that need attention and quick actions"></div>
        <div class="device hand"><div class="frame"><div class="screen"><div class="status light"><span>9:41</span><span class="sicons"><svg viewBox="0 0 18 12"><path d="M1 11h2V8H1zm4 0h2V6H5zm4 0h2V4H9zm4 0h2V1h-2z"/></svg><svg viewBox="0 0 16 12"><path d="M8 11.5 1 4.3a10 10 0 0 1 14 0zm0-2.8 3.4-3.5a5 5 0 0 0-6.8 0z" fill-opacity=".35"/><path d="M8 11.5 4.6 8.1a4.8 4.8 0 0 1 6.8 0z"/></svg><svg viewBox="0 0 26 12"><rect x=".5" y=".5" width="21" height="11" rx="3" fill="none" stroke="currentColor" stroke-opacity=".5"/><rect x="2" y="2" width="16" height="8" rx="1.8"/><rect x="23" y="4" width="2" height="4" rx="1" fill-opacity=".5"/></svg></span></div><span class="camera"></span><img src="/images/screens/phone-home.webp" width="780" height="1688" alt="Medikabiz on an Android phone: home screen with stock value and alerts"></div></div></div>
      </figure>
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
      <p class="lede">Medikabiz helps owners run routine work the same way every day, instead of relying on memory, registers and scattered slips.</p>
    </div>
    <div class="trio">
      <div class="problem"><span class="dot" style="background: var(--amber)"></span><h3>When stock is hard to track</h3><p>Manual checks make it hard to know what is on the shelf and what needs to be ordered again.</p></div>
      <div class="problem"><span class="dot" style="background: var(--coral)"></span><h3>When expiry is easy to miss</h3><p>A warning window you set brings medicines that are expiring soon, or already expired, to your attention.</p></div>
      <div class="problem"><span class="dot" style="background: var(--blue)"></span><h3>When balances are unclear</h3><p>Bill history and unpaid balances show who owes what, so payment follow-up doesn't depend on a notebook.</p></div>
    </div>
    <p class="answer"><span class="eyebrow">Medikabiz answer</span><strong>A dashboard, filters, alerts, billing and reports in one place.</strong></p>
  </div>
</section>

<section class="band" aria-labelledby="shotsh" style="padding-top: 0">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">See it at work</span>
      <h2 id="shotsh">The real app, on the counter and in your pocket</h2>
    </div>
    <div class="gallery">
      <figure class="wide">
        <div class="window"><div class="bar"><span class="bar-title"><img src="/images/favicon.svg" alt="" width="14" height="14">Medikabiz</span><span class="bar-ctl" aria-hidden="true"><i>–</i><i>▢</i><i>✕</i></span></div><img src="/images/screens/desktop-inventory.webp" width="1600" height="1000" loading="lazy" alt="Inventory table on a computer with stock, batches, MRP, nearest expiry and status for each medicine"></div>
        <figcaption><b>Every medicine, every batch</b>Stock in strips and loose tablets, MRP, the nearest expiry and a clear status. Filter to low stock, expiring soon or expired in one tap.</figcaption>
      </figure>
      <figure class="tall">
        <div class="device "><div class="frame"><div class="screen"><div class="status dark"><span>9:41</span><span class="sicons"><svg viewBox="0 0 18 12"><path d="M1 11h2V8H1zm4 0h2V6H5zm4 0h2V4H9zm4 0h2V1h-2z"/></svg><svg viewBox="0 0 16 12"><path d="M8 11.5 1 4.3a10 10 0 0 1 14 0zm0-2.8 3.4-3.5a5 5 0 0 0-6.8 0z" fill-opacity=".35"/><path d="M8 11.5 4.6 8.1a4.8 4.8 0 0 1 6.8 0z"/></svg><svg viewBox="0 0 26 12"><rect x=".5" y=".5" width="21" height="11" rx="3" fill="none" stroke="currentColor" stroke-opacity=".5"/><rect x="2" y="2" width="16" height="8" rx="1.8"/><rect x="23" y="4" width="2" height="4" rx="1" fill-opacity=".5"/></svg></span></div><span class="camera"></span><img src="/images/screens/phone-new-bill.webp" width="780" height="1688" loading="lazy" alt="New bill on a phone with Dolo 650, Allegra 120 and Pan 40, total 437 rupees"></div></div></div>
        <figcaption><b>Bill at the counter</b>Search or scan, pick the batch, add strips or loose tablets. GST is worked out for you.</figcaption>
      </figure>
      <figure class="tall">
        <div class="device "><div class="frame"><div class="screen"><div class="status dark"><span>9:41</span><span class="sicons"><svg viewBox="0 0 18 12"><path d="M1 11h2V8H1zm4 0h2V6H5zm4 0h2V4H9zm4 0h2V1h-2z"/></svg><svg viewBox="0 0 16 12"><path d="M8 11.5 1 4.3a10 10 0 0 1 14 0zm0-2.8 3.4-3.5a5 5 0 0 0-6.8 0z" fill-opacity=".35"/><path d="M8 11.5 4.6 8.1a4.8 4.8 0 0 1 6.8 0z"/></svg><svg viewBox="0 0 26 12"><rect x=".5" y=".5" width="21" height="11" rx="3" fill="none" stroke="currentColor" stroke-opacity=".5"/><rect x="2" y="2" width="16" height="8" rx="1.8"/><rect x="23" y="4" width="2" height="4" rx="1" fill-opacity=".5"/></svg></span></div><span class="camera"></span><img src="/images/screens/phone-alerts.webp" width="780" height="1688" loading="lazy" alt="Alerts on a phone listing expired, expiring and low-stock medicines"></div></div></div>
        <figcaption><b>Alerts before it's too late</b>Expired, expiring soon and low-stock medicines in one list.</figcaption>
      </figure>
      <figure class="tall">
        <div class="device "><div class="frame"><div class="screen"><div class="status dark"><span>9:41</span><span class="sicons"><svg viewBox="0 0 18 12"><path d="M1 11h2V8H1zm4 0h2V6H5zm4 0h2V4H9zm4 0h2V1h-2z"/></svg><svg viewBox="0 0 16 12"><path d="M8 11.5 1 4.3a10 10 0 0 1 14 0zm0-2.8 3.4-3.5a5 5 0 0 0-6.8 0z" fill-opacity=".35"/><path d="M8 11.5 4.6 8.1a4.8 4.8 0 0 1 6.8 0z"/></svg><svg viewBox="0 0 26 12"><rect x=".5" y=".5" width="21" height="11" rx="3" fill="none" stroke="currentColor" stroke-opacity=".5"/><rect x="2" y="2" width="16" height="8" rx="1.8"/><rect x="23" y="4" width="2" height="4" rx="1" fill-opacity=".5"/></svg></span></div><span class="camera"></span><img src="/images/screens/phone-supplier-bills.webp" width="780" height="1688" loading="lazy" alt="Supplier bills on a phone: two being read, three ready to check"></div></div></div>
        <figcaption><b>Supplier bills, read for you</b>Add a pile of bills at once. Each one is ready to check in moments.</figcaption>
      </figure>
    </div>
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
          <p>Photograph your supplier's bills or pick their PDFs, as many as you have. Medikabiz reads the medicines, batches, expiry dates and rates. You check each item, and only then is it added to stock.</p>
        </div>
      </article>
    </div>
  </div>
</section>

<section class="band" aria-labelledby="dayh">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">A day with Medikabiz</span>
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
      <h2 id="price">Try Medikabiz free for 7 days</h2>
      <p class="lede">Use the whole app first, then choose monthly or yearly.</p>
    </div>
    <div class="plans">
      <div class="plan trialcard">
        <div class="plan-top">
          <span class="name">Free trial</span>
          <p class="amount">₹0</p>
          <p class="per">for 7 days</p>
          <p class="note">Try the whole app in your own shop before you pay.</p>
        </div>
        <a class="btn btn-teal" href="#contact">Start free trial</a>
        <ul class="includes">
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Every feature, nothing locked</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Set up your shop and bring in your stock</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Nothing to pay to start</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Your data stays when you choose a plan</li>
        </ul>
      </div>
      <div class="plan paid">
        <div class="plan-top">
          <span class="name">Monthly</span>
          <p class="amount">₹99</p>
          <p class="per">per month</p>
          <p class="note">Pay month by month.</p>
        </div>
        <a class="btn btn-navy" href="#contact">Choose monthly</a>
        <ul class="includes">
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Unlimited medicines, batches and bills</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>GST bills on A4 or 80 mm printers, shared on WhatsApp</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Low-stock and expiry alerts, daily reminder</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Customer balances and payment follow-up</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Purchases, suppliers and returns</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Reports, profit and GST-ready data</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Supplier bills read from photos and PDFs</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Phone and computer, always in sync</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>WhatsApp support</li>
        </ul>
      </div>
      <div class="plan paid best">
        <span class="badge">Best value</span>
        <div class="plan-top">
          <span class="name">Yearly</span>
          <p class="amount">₹999</p>
          <p class="per">per year</p>
          <p class="note"><b>Just ₹83 a month</b>, billed yearly. Save ₹189 compared with paying monthly.</p>
        </div>
        <a class="btn btn-teal" href="#contact">Choose yearly</a>
        <ul class="includes">
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Unlimited medicines, batches and bills</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>GST bills on A4 or 80 mm printers, shared on WhatsApp</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Low-stock and expiry alerts, daily reminder</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Customer balances and payment follow-up</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Purchases, suppliers and returns</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Reports, profit and GST-ready data</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Supplier bills read from photos and PDFs</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>Phone and computer, always in sync</li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>WhatsApp support</li>
        </ul>
      </div>
    </div>
    <div class="devices"><span><b>Android</b> phone</span><span><b>Windows</b> computer</span><span><b>Mac</b></span><span>One account for all your shop's devices</span></div>
  </div>
</section>

<section class="band" id="download" aria-labelledby="dlh">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">Download</span>
      <h2 id="dlh">Get Medikabiz on every device in your shop</h2>
      <p class="lede">One account works on all of them: bill at the counter computer, check stock on your phone. Install, sign up, and your 7-day trial starts.</p>
    </div>
    <div class="downloads">
      <article class="dl">
        <div class="dl-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 9.5h10V17a1 1 0 0 1-1 1h-1v2.5a1 1 0 0 1-2 0V18h-2v2.5a1 1 0 0 1-2 0V18H8a1 1 0 0 1-1-1zM5 10a1 1 0 0 1 2 0v5a1 1 0 0 1-2 0zm12 0a1 1 0 0 1 2 0v5a1 1 0 0 1-2 0zM7.2 8.5a4.8 4.8 0 0 1 2.3-3.6L8.6 3.4a.4.4 0 0 1 .7-.4l.9 1.5a5 5 0 0 1 3.6 0l.9-1.5a.4.4 0 0 1 .7.4l-.9 1.5a4.8 4.8 0 0 1 2.3 3.6zM10 6.6a.7.7 0 1 0 0 1.4.7.7 0 0 0 0-1.4zm4 0a.7.7 0 1 0 0 1.4.7.7 0 0 0 0-1.4z"/></svg></div>
        <h3>Android phone or tablet</h3>
        <p class="req">Android 7.0 or newer · 101 MB</p>
        <a class="btn btn-navy" href="/downloads/Medikabiz.apk">Download for Android</a>
        <p class="tip">Open the downloaded file and tap <b>Install</b>. If your phone asks, allow installing apps from your browser.</p>
      </article>
      <article class="dl">
        <div class="dl-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 5.3l7.4-1v7.2H3zm8.4-1.2L21 2.8v8.7h-9.6zM3 12.5h7.4v7.2L3 18.7zm8.4 0H21v8.7l-9.6-1.3z"/></svg></div>
        <h3>Windows computer</h3>
        <p class="req">Windows 10 or 11, 64-bit · 21 MB</p>
        <a class="btn btn-navy" href="/downloads/Medikabiz-Setup.exe">Download for Windows</a>
        <p class="tip">Run the installer. If Windows shows "Windows protected your PC", click <b>More info</b>, then <b>Run anyway</b>.</p>
      </article>
      <article class="dl">
        <div class="dl-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7a4.5 4.5 0 0 0-3.5-1.9c-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8A4.7 4.7 0 0 0 4.2 9.5c-1.7 2.9-.4 7.3 1.2 9.7.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4a10 10 0 0 0 1.3-2.8 4.3 4.3 0 0 1-2.7-3.8zM14 5.5a4.3 4.3 0 0 0 1-3.1 4.4 4.4 0 0 0-2.9 1.5 4.1 4.1 0 0 0-1 3 3.7 3.7 0 0 0 2.9-1.4z"/></svg></div>
        <h3>Mac</h3>
        <p class="req">macOS 12 or newer · 35 MB</p>
        <a class="btn btn-navy" href="/downloads/Medikabiz.dmg">Download for Mac</a>
        <p class="tip">Open the file and drag <b>Medikabiz</b> into your Applications folder.</p>
      </article>
    </div>
    <p class="dl-help">Need help installing? Message us on WhatsApp at <b>+91 70537 92466</b> and we'll set it up with you.</p>
  </div>
</section>

<section class="band" aria-labelledby="missionh">
  <div class="wrap">
    <div class="head">
      <span class="eyebrow">Purpose-led</span>
      <h2 id="missionh">Useful technology with a social mission</h2>
      <p class="lede">Medikabiz operates under Yatharthvadi Foundation, a Section 8 company.</p>
    </div>
    <div class="mission">
      <div class="heart" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 21s-7.5-4.6-9.6-9.2C.9 8.5 2.9 4.5 6.6 4.5c2.1 0 3.6 1.1 5.4 3 1.8-1.9 3.3-3 5.4-3 3.7 0 5.7 4 4.2 7.3C19.5 16.4 12 21 12 21z"/></svg></div>
      <div><p class="who">Medikabiz</p><h3>Practical tools for pharmacy owners.</h3></div>
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
        <a class="btn btn-teal" href="https://wa.me/917053792466?text=Hello%2C%20I%20want%20to%20try%20Medikabiz">Message us on WhatsApp</a>
        <span>or call or WhatsApp</span>
        <span class="num">+91 70537 92466</span>
      </div>
    </div>
    <footer>
      <span>Medikabiz · Pharmacy management, made simpler</span>
      <span>A Yatharthvadi Foundation initiative</span>
    </footer>
  </div>
</section>

</body>
</html>
