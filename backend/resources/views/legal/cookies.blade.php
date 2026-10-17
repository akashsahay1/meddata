@extends('legal.layout')
@section('title', 'Cookie Policy')
@section('content')
<div class="summary">
  <p><b>In short:</b> our website uses only the cookies it needs to work securely. No advertising cookies, no tracking, no analytics.</p>
</div>

<h2>1. What cookies are</h2>
<p>Cookies are small files a website saves in your browser, so it can remember something between pages.</p>

<h2>2. The cookies we use</h2>
<div class="table-wrap"><table>
  <tr><th>Cookie</th><th>What it does</th><th>How long</th></tr>
  <tr><td>{{ config('session.cookie') }}</td><td>Keeps a visit or a sign-in to the website working</td><td>{{ config('session.lifetime') }} minutes of inactivity</td></tr>
  <tr><td>XSRF-TOKEN</td><td>Protects forms against misuse from other websites</td><td>{{ config('session.lifetime') }} minutes</td></tr>
</table></div>
<p>These are strictly necessary, so they don't need your consent. You can block or delete cookies in your browser settings; parts of the website, such as signing in, may then stop working.</p>

<h2>3. Fonts</h2>
<p>The website loads its fonts from Google Fonts. Your browser contacts Google's servers to fetch them, which shares your IP address with Google. Google Fonts does not set cookies.</p>

<h2>4. The apps</h2>
<p>The Medikabiz apps don't use cookies. They keep your sign-in in your device's secure storage and your records in the app's own storage.</p>

<h2>5. Contact</h2>
<p>Questions? Email <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a> or see our <a href="/privacy-policy">Privacy Policy</a>.</p>
@endsection
