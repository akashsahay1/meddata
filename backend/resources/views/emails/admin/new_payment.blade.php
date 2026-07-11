@extends('emails.layout')

@section('title', 'New Meddata payment')

@section('content')
    <h1 style="margin:0 0 16px; color:#0d1b2a; font-size:20px; font-weight:700;">
        {{ $isRenewal ? 'Subscription renewed' : 'New payment received' }} 💰
    </h1>

    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 8px; border:1px solid #eceff1; border-radius:8px;">
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Customer</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#0d1b2a; font-size:14px; font-weight:600; text-align:right;">{{ $user->name }} ({{ $user->email }})</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Plan</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#0d1b2a; font-size:14px; text-align:right;">{{ $planName }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Amount</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#1f7a45; font-size:14px; font-weight:700; text-align:right;">{{ $currency }} {{ number_format($amount, 2) }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Payment ID</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#3d4852; font-size:13px; text-align:right; font-family:'Courier New', monospace;">{{ $paymentId }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; color:#8a97a3; font-size:13px;">When</td>
            <td style="padding:12px 16px; color:#0d1b2a; font-size:14px; text-align:right;">{{ now()->format('d M Y, H:i') }}</td>
        </tr>
    </table>
@endsection
