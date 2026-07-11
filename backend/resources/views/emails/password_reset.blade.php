@extends('emails.layout')

@section('title', 'Your Meddata password reset code')

@section('content')
    <h1 style="margin:0 0 16px; color:#0d1b2a; font-size:22px; font-weight:700;">Password reset</h1>

    <p style="margin:0 0 20px; color:#3d4852; font-size:15px; line-height:24px;">
        We received a request to reset the password for your Meddata account. Enter the
        code below in the app to continue. This code expires in <strong>{{ $ttlMinutes }} minutes</strong>.
    </p>

    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 20px;">
        <tr>
            <td align="center" style="background-color:#f0f4f8; border:1px dashed #c3ced9; border-radius:10px; padding:20px;">
                <span style="font-size:34px; font-weight:700; letter-spacing:10px; color:#0d1b2a; font-family:'Courier New', monospace;">{{ $code }}</span>
            </td>
        </tr>
    </table>

    <p style="margin:0; color:#8a97a3; font-size:13px; line-height:20px;">
        If you didn't request a password reset, you can safely ignore this email - your
        password will not change. For your security, never share this code with anyone.
    </p>
@endsection
