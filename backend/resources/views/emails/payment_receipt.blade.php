@extends('emails.layout')

@section('title', $isRenewal ? 'Your Meddata subscription was renewed' : 'Your Meddata payment receipt')

@section('content')
    <h1 style="margin:0 0 16px; color:#0d1b2a; font-size:22px; font-weight:700;">
        {{ $isRenewal ? 'Subscription renewed ✅' : 'Payment received ✅' }}
    </h1>

    <p style="margin:0 0 20px; color:#3d4852; font-size:15px; line-height:24px;">
        Hi {{ $user->name }}, thank you for your {{ $isRenewal ? 'renewal' : 'purchase' }}.
        Your Meddata Premium is active.
    </p>

    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 20px; border:1px solid #eceff1; border-radius:8px;">
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Plan</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#0d1b2a; font-size:14px; font-weight:600; text-align:right;">{{ $planName }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Amount paid</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#0d1b2a; font-size:14px; font-weight:600; text-align:right;">{{ $currency }} {{ number_format($amount, 2) }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Payment ID</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#3d4852; font-size:13px; text-align:right; font-family:'Courier New', monospace;">{{ $paymentId }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; color:#8a97a3; font-size:13px;">Valid until</td>
            <td style="padding:12px 16px; color:#0d1b2a; font-size:14px; font-weight:600; text-align:right;">{{ $expiry ? \Illuminate\Support\Carbon::parse($expiry)->format('d M Y') : 'Lifetime' }}</td>
        </tr>
    </table>

    <p style="margin:0; color:#8a97a3; font-size:13px; line-height:20px;">
        Keep this email as your receipt. If anything looks wrong, reply to this message and
        we'll sort it out.
    </p>
@endsection
