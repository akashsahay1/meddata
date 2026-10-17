@extends('legal.layout')
@section('title', 'Delivery Policy')
@section('content')
<p>Medikabiz is software. Nothing physical is shipped.</p>

<h2>1. Getting the app</h2>
<p>The apps for Android, Windows and Mac are downloaded from <a href="/#download">our website</a>, or sent to you by our team on WhatsApp. You can use them as soon as they are installed.</p>

<h2>2. When your plan starts</h2>
<p>Your plan is activated in the app as soon as Razorpay confirms your payment, usually within a minute. You get a receipt by email. If your plan hasn't started within 24 hours of a successful payment, contact us and we will activate it or refund you in full, as our <a href="/refund-policy">Refund &amp; Cancellation Policy</a> explains.</p>

<h2>3. Where we serve</h2>
<p>Medikabiz is offered to businesses in India. Prices are in Indian rupees.</p>

<h2>4. Contact</h2>
<p>Email: <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a> · WhatsApp: {{ config('legal.phone') }}</p>
@endsection
