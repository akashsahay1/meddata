@extends('emails.layout')

@section('title', 'Welcome to Meddata')

@section('content')
    <h1 style="margin:0 0 16px; color:#0d1b2a; font-size:22px; font-weight:700;">Welcome, {{ $user->name }} 👋</h1>

    <p style="margin:0 0 16px; color:#3d4852; font-size:15px; line-height:24px;">
        Your Meddata account is ready. You can now track your medicine stock, get expiry
        reminders, and keep everything backed up securely.
    </p>

    @if(($entitlement['premium'] ?? false) && ($entitlement['source'] ?? null) === 'trial')
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 20px; background-color:#eaf5ee; border-radius:8px;">
            <tr>
                <td style="padding:16px 18px;">
                    <p style="margin:0; color:#1f7a45; font-size:15px; font-weight:600;">
                        🎉 Your {{ $entitlement['days_left'] ?? 7 }}-day free trial is active
                    </p>
                    <p style="margin:6px 0 0; color:#3d6b4d; font-size:13px;">
                        Full access until {{ isset($entitlement['trial_ends_at']) ? \Illuminate\Support\Carbon::parse($entitlement['trial_ends_at'])->format('d M Y') : '' }}.
                    </p>
                </td>
            </tr>
        </table>
    @endif

    <p style="margin:0 0 8px; color:#3d4852; font-size:15px; line-height:24px;">A few things you can do right away:</p>
    <ul style="margin:0 0 20px; padding-left:20px; color:#3d4852; font-size:15px; line-height:24px;">
        <li>Add your medicines and set expiry dates</li>
        <li>Enable low-stock and expiry notifications</li>
        <li>Back up your data to restore it on any device</li>
    </ul>

    <p style="margin:0; color:#8a97a3; font-size:14px; line-height:22px;">
        Questions? Just reply to this email - we're happy to help.
    </p>
@endsection
