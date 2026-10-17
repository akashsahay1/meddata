@extends('legal.layout')
@section('title', 'Terms of Service')
@section('content')
<div class="summary">
  <p><b>In short:</b> Medikabiz is a tool to help you run your pharmacy. You stay responsible for your shop, your medicines, your bills and your tax filings. Try it free for 7 days; after that, a plan is paid in advance and doesn't renew by itself. Your data is yours.</p>
</div>

<h2>1. About these terms</h2>
<p>These terms are an agreement between you and {{ config('legal.company') }}, a Section 8 company registered in India ("we", "us"), for the use of Medikabiz: the apps for Android, Windows and Mac, and the website medikabiz.com (together, "the service"). By creating an account or using the service, you accept these terms and our <a href="/privacy-policy">Privacy Policy</a>. If you use it for a business, you accept them for that business.</p>

<h2>2. Who can use Medikabiz</h2>
<p>You must be at least 18 and able to enter a contract under Indian law. Medikabiz is meant for pharmacies and medical stores; you are responsible for holding the licences your business needs, such as drug licences and GST registration.</p>

<h2>3. Your account</h2>
<ul>
  <li>Give correct details and keep them up to date.</li>
  <li>Keep your password safe. You are responsible for what happens under your account, including on every device you link to your shop.</li>
  <li>Tell us at once if you think someone else is using your account.</li>
</ul>

<h2>4. Free trial</h2>
<p>A new shop gets a 7-day free trial with every feature. Nothing is charged during the trial and no payment details are needed. At the end of the trial, choose a plan to keep adding and changing records; your data stays safe either way.</p>

<h2>5. Plans and payment</h2>
<ul>
  <li>Plans and prices are shown in the app and on <a href="/#pricing">our website</a> (currently ₹99 a month or ₹999 a year). Prices are in Indian rupees; taxes apply as required by law.</li>
  <li>You pay in advance through Razorpay. Your plan starts as soon as the payment is confirmed.</li>
  <li><b>Plans don't renew automatically.</b> When a plan ends, you can pay again to continue; we never charge you without your action.</li>
  <li>We may change prices. A change never affects a period you have already paid for.</li>
  <li>Refunds are covered by our <a href="/refund-policy">Refund &amp; Cancellation Policy</a>.</li>
</ul>

<h2>6. Your data</h2>
<p>The records you put into Medikabiz belong to you. You give us permission to store, process and sync them only to provide the service, as described in our Privacy Policy. You can export your stock to Excel and keep backups at any time. You are responsible for having the right to any data you enter, including your customers' details.</p>

<h2>7. Your responsibilities</h2>
<ul>
  <li>Sell medicines only as the law allows, including prescription rules under the Drugs and Cosmetics Act, 1940 and its rules. Medikabiz does not check prescriptions.</li>
  <li>Check stock, batch numbers, expiry dates, prices and bills before you rely on them. Alerts are reminders, not a guarantee.</li>
  <li>Check GST figures with your accountant before filing. Medikabiz prepares data for returns; it doesn't file them.</li>
  <li>Review every line read from a supplier bill before adding it to stock. AI reading can make mistakes.</li>
</ul>

<h2>8. Acceptable use</h2>
<p>Don't use the service for anything unlawful, try to break or overload it, access another shop's data, copy or resell the app, or reverse engineer it except where the law allows.</p>

<h2>9. Our service</h2>
<ul>
  <li>We work to keep Medikabiz available and your data safe, but we can't promise it will never be interrupted, for example during maintenance, internet problems or outages at our providers. The app keeps working offline and syncs when the connection returns.</li>
  <li>We may improve, change or remove features. If we remove something important you pay for, we will tell you in advance.</li>
  <li>Medikabiz and its design, code and name belong to {{ config('legal.company') }}. We give you a personal, non-transferable right to use it while your account is active.</li>
</ul>

<h2>10. Disclaimers</h2>
<p>The service is provided "as is". To the extent the law allows, we don't give any warranty that it is free of errors or fit for a particular purpose. See also our <a href="/disclaimer">Disclaimer</a>.</p>

<h2>11. Limit of liability</h2>
<p>To the extent the law allows, we are not liable for indirect or consequential losses, such as lost profit, lost business or penalties, arising from your use of the service. Our total liability for any claim is limited to the amount you paid us in the 12 months before the claim.</p>

<h2>12. Indemnity</h2>
<p>You agree to compensate us for claims made by others because you broke these terms or the law while using the service.</p>

<h2>13. Ending the agreement</h2>
<p>You can stop using Medikabiz at any time and ask us to delete your account. We may suspend or close an account that breaks these terms or the law, after a warning where reasonable. On closure we keep records only as long as the law requires.</p>

<h2>14. Law and disputes</h2>
<p>These terms are governed by the laws of India. We will first try to settle any dispute with you directly. If that fails, the courts at {{ config('legal.jurisdiction') }} have exclusive jurisdiction.</p>

<h2>15. Changes to these terms</h2>
<p>We may update these terms. We will tell you in the app or by email before an important change takes effect. If you keep using the service after that, the new terms apply.</p>

<h2>16. Contact</h2>
<p>{{ config('legal.company') }}, {{ config('legal.address') }}<br>
Email: <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a> · WhatsApp: {{ config('legal.phone') }}</p>
@endsection
