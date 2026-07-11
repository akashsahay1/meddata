@extends('emails.layout')

@section('title', 'New Meddata signup')

@section('content')
    <h1 style="margin:0 0 16px; color:#0d1b2a; font-size:20px; font-weight:700;">New customer signup</h1>

    <p style="margin:0 0 20px; color:#3d4852; font-size:15px; line-height:24px;">
        A new user just created a Meddata account.
    </p>

    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 8px; border:1px solid #eceff1; border-radius:8px;">
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Name</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#0d1b2a; font-size:14px; font-weight:600; text-align:right;">{{ $user->name }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#8a97a3; font-size:13px;">Email</td>
            <td style="padding:12px 16px; border-bottom:1px solid #eceff1; color:#0d1b2a; font-size:14px; text-align:right;">{{ $user->email }}</td>
        </tr>
        <tr>
            <td style="padding:12px 16px; color:#8a97a3; font-size:13px;">Signed up</td>
            <td style="padding:12px 16px; color:#0d1b2a; font-size:14px; text-align:right;">{{ $user->created_at?->format('d M Y, H:i') }}</td>
        </tr>
    </table>
@endsection
