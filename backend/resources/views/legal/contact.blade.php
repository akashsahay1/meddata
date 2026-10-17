@extends('legal.layout')
@section('title', 'Contact Us')
@section('content')
<div class="summary">
  <p><b>Fastest:</b> message us on WhatsApp at <b>{{ config('legal.phone') }}</b>. We help with installing, setting up your shop, plans and payments.</p>
</div>

<h2>Support</h2>
<p>WhatsApp and phone: {{ config('legal.phone') }}<br>
Email: <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a></p>

<h2>Company</h2>
<p>Medikabiz is a product of {{ config('legal.company') }}, a Section 8 company.<br>
Registered office: {{ config('legal.address') }}</p>

<h2>Grievance officer</h2>
<p>For complaints about the service or about your personal data:<br>
{{ config('legal.grievance_officer') }}, {{ config('legal.company') }}<br>
Email: <a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a></p>
<p>We acknowledge a complaint within 24 hours and resolve it within 15 days.</p>
@endsection
