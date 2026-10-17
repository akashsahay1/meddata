<!doctype html>
<html lang="en-IN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>@yield('title') · Medikabiz</title>
<meta name="description" content="@yield('title') for Medikabiz, the pharmacy stock and billing app by {{ config('legal.company') }}.">
<link rel="icon" href="/images/favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:wght@600;700;800&family=Figtree:wght@400;500;600;700&display=swap">
<link rel="stylesheet" href="/css/site.css">
<style>
.legal-hero { padding-block: 48px 40px; }
.legal-hero h1 { font-size: clamp(2rem, 4.4vw, 3rem); }
.legal-hero p { color: var(--mist); margin-top: 12px; }
.legal { max-width: var(--wrap); margin: 0 auto; }
.legal h2 { font-size: 1.35rem; margin: 40px 0 12px; }
.legal h3 { font-size: 1.05rem; margin: 24px 0 8px; }
.legal p, .legal li { color: #2C3B52; }
.legal p { margin: 0 0 14px; }
.legal ul { margin: 0 0 14px; padding-left: 22px; display: grid; gap: 6px; }
.legal a { color: var(--teal-ink); font-weight: 600; }
.legal .summary { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 20px 22px; margin-bottom: 8px; }
.legal .summary p:last-child { margin: 0; }
.legal table { width: 100%; border-collapse: collapse; margin: 0 0 16px; font-size: .95rem; }
.legal th, .legal td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }
.legal th { font-family: var(--display); color: var(--ink); }
.table-wrap { overflow-x: auto; }
</style>
</head>
<body>
@include('partials.site-header')

<section class="band dark legal-hero">
  <div class="wrap">
    <span class="eyebrow">Legal</span>
    <h1>@yield('title')</h1>
    <p>Last updated {{ config('legal.updated') }}</p>
  </div>
</section>

<main class="band">
  <article class="legal">
    @yield('content')
  </article>
</main>

@include('partials.site-footer')
</body>
</html>
