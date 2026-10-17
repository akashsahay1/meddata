@extends('legal.layout')
@section('title', 'Refund & Cancellation Policy')
@section('content')
<div class="summary">
  <p><b>In short:</b> try every feature free for 7 days before you pay. Plans don't renew by themselves, so there is nothing to cancel. If you were charged twice, or paid and your plan didn't start, we refund you in full.</p>
</div>

<h2>1. Try before you pay</h2>
<p>Every new shop gets a 7-day free trial with every feature, and no payment details are asked for. Please use the trial to decide whether Medikabiz suits your shop.</p>

<h2>2. Cancelling</h2>
<p>Plans are paid in advance and <b>do not renew automatically</b>. You don't need to cancel anything: when your plan ends, simply don't buy another. Your plan stays active until the end of the period you paid for.</p>

<h2>3. Refunds</h2>
<p>Because you can try the full app free first, a plan that has started is not refundable, in full or in part, including for unused days. We do refund in full when:</p>
<ul>
  <li>you were charged more than once for the same plan;</li>
  <li>money left your account but your plan was not activated and we can't activate it;</li>
  <li>we close the service or a paid feature you rely on before your paid period ends (a refund for the unused part).</li>
</ul>

<h2>4. How to ask for a refund</h2>
<p>Message us on WhatsApp at {{ config('legal.phone') }} or email <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a> within 30 days of the payment, with your registered mobile number or email and the payment reference from your receipt. We reply within 2 working days.</p>

<h2>5. When you get the money</h2>
<p>An approved refund is sent to the account or card you paid from, through Razorpay, within 5 to 7 working days. Your bank may take a few more days to show it.</p>

<h2>6. Contact</h2>
<p>{{ config('legal.company') }}, {{ config('legal.address') }}<br>
Email: <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a> · WhatsApp: {{ config('legal.phone') }}</p>
@endsection
