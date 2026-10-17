@extends('legal.layout')
@section('title', 'Privacy Policy')
@section('content')
<div class="summary">
  <p><b>In short:</b> we collect what the app needs to run your shop: your account, your shop's details, its stock and bills. We use it only to provide Medikabiz. We don't sell it, we don't show ads, and the app has no tracking or advertising tools. You can ask us to see, correct or delete your data at any time.</p>
</div>

<h2>1. Who we are</h2>
<p>Medikabiz ("the app", "we", "us") is provided by {{ config('legal.company') }}, a Section 8 company registered in India, at {{ config('legal.address') }}. This policy explains how we handle personal data when you use the Medikabiz apps for Android, Windows and Mac, and the website medikabiz.com. It is written to meet the Digital Personal Data Protection Act, 2023 and the Information Technology Act, 2000 and its rules.</p>

<h2>2. What we collect</h2>
<div class="table-wrap"><table>
  <tr><th>What</th><th>Examples</th><th>Why</th></tr>
  <tr><td>Your account</td><td>Name, email address, mobile number, password (stored only as a secure hash), profile photo if you add one</td><td>To sign you in, secure your account and contact you about it</td></tr>
  <tr><td>Your shop's details</td><td>Shop name, address, GSTIN, drug licence numbers, pharmacist's name and registration, FSSAI number, invoice settings</td><td>To print them on your bills and prepare GST data, as the law requires</td></tr>
  <tr><td>Your business records</td><td>Medicines, batches, stock, purchases, suppliers, bills, payments, returns</td><td>To run the app and keep every device of your shop in sync</td></tr>
  <tr><td>Your customers' details</td><td>Names, phone numbers and addresses you enter on bills</td><td>To make and share bills and track balances, on your instructions</td></tr>
  <tr><td>Supplier bills you scan</td><td>Photos or PDFs of purchase invoices</td><td>To read the medicines, batches and rates for you</td></tr>
  <tr><td>Payments</td><td>Plan bought, amount, payment reference and status</td><td>To activate your plan and keep tax records</td></tr>
  <tr><td>Device details</td><td>A device identifier, device name, app version</td><td>To link your devices to your shop and fix problems</td></tr>
  <tr><td>Support messages</td><td>WhatsApp messages, emails and feedback you send us</td><td>To help you</td></tr>
</table></div>
<p>We never see your card, UPI or bank details. Payments are handled by Razorpay, which is licensed by the Reserve Bank of India.</p>

<h2>3. Your customers' data</h2>
<p>When you enter your customers' details, you decide what is collected and why; for that data you are the "data fiduciary" and we process it only on your behalf, to provide the app. Please collect only what you need and tell your customers how you use it.</p>

<h2>4. How we use your data</h2>
<ul>
  <li>To provide the app: storing and syncing your records, making bills, alerts and reports.</li>
  <li>To read supplier bills you choose to scan (see section 6).</li>
  <li>To manage your trial and plan, and to send receipts and important account emails.</li>
  <li>To give support, fix errors and keep the service secure, including preventing misuse.</li>
  <li>To meet legal duties, such as tax and accounting records.</li>
</ul>
<p>We don't use your data for advertising, we don't sell it, and we don't build profiles of you or your customers.</p>

<h2>5. Who we share it with</h2>
<p>Only with the service providers we need to run Medikabiz, each under a contract or terms that limit how they use it:</p>
<ul>
  <li><b>Our hosting provider</b>, which runs the servers that store your data.</li>
  <li><b>Razorpay</b>, to take payments.</li>
  <li><b>Groq, Inc.</b>, an AI service in the United States, which reads supplier bills you scan (section 6).</li>
  <li><b>Our email provider</b>, to send account and payment emails.</li>
  <li><b>Authorities</b>, only when the law requires it.</li>
</ul>

<h2>6. Reading supplier bills with AI</h2>
<p>When you scan a supplier bill, the file (or the text inside a PDF) is sent to Groq, Inc. in the United States to be read. Supplier bills contain business details such as the supplier's name, GSTIN, medicines and rates. We keep the file on our server for up to 30 days, so you can try again if reading fails, and then delete it. Nothing from a scanned bill is added to your stock until you check it and confirm. If you prefer, type the bill in by hand instead; nothing is then sent to an AI service.</p>

<h2>7. Where your data is kept</h2>
<p>Your records are kept on our servers and, for offline use, on your own devices. Some providers above (such as Groq) process data outside India. We transfer data abroad only as the law allows.</p>

<h2>8. How long we keep it</h2>
<ul>
  <li>Your account and shop records: while your account exists. If you ask us to delete your account, we delete them within 30 days, except what the law makes us keep.</li>
  <li>Bills, purchases and payment records: up to 8 years, as GST and tax laws require businesses to keep them.</li>
  <li>Scanned supplier bills: 30 days.</li>
</ul>

<h2>9. How we protect it</h2>
<p>Data travels over encrypted connections (HTTPS). Passwords are stored only as secure hashes. On your device, your sign-in is kept in the system's secure storage. Only people who need it to run the service can reach our servers. No system is perfectly secure; if a breach affects you, we will tell you and the authorities as the law requires.</p>

<h2>10. Your rights</h2>
<p>Under the Digital Personal Data Protection Act, 2023 you can:</p>
<ul>
  <li>ask what data we hold about you and how we use it;</li>
  <li>ask us to correct, complete or update it;</li>
  <li>ask us to delete it, and withdraw consent at any time;</li>
  <li>nominate someone to act for you if you die or cannot act;</li>
  <li>complain to us (section 12) and, if not satisfied, to the Data Protection Board of India.</li>
</ul>
<p>To use these rights, message us on WhatsApp or email us (section 12). We reply within 30 days.</p>

<h2>11. Children</h2>
<p>Medikabiz is for businesses. It is not meant for anyone under 18, and we don't knowingly collect children's data.</p>

<h2>12. Contact and grievance officer</h2>
<p>Grievance officer: {{ config('legal.grievance_officer') }}<br>
{{ config('legal.company') }}, {{ config('legal.address') }}<br>
Email: <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a> · WhatsApp: {{ config('legal.phone') }}</p>
<p>We acknowledge a complaint within 24 hours and resolve it within 15 days.</p>

<h2>13. Changes</h2>
<p>If we change this policy, we update the date at the top. If a change matters to how we use your data, we tell you in the app or by email before it takes effect.</p>
@endsection
