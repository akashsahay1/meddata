<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>@yield('title', 'Meddata')</title>
</head>
<body style="margin:0; padding:0; background-color:#f4f5f7; -webkit-font-smoothing:antialiased; font-family:'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f5f7; padding:24px 0;">
        <tr>
            <td align="center">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; background-color:#ffffff; border-radius:12px; overflow:hidden; box-shadow:0 1px 3px rgba(0,0,0,0.06);">
                    <!-- Header -->
                    <tr>
                        <td style="background-color:#0d1b2a; padding:24px 32px;">
                            <span style="color:#ffffff; font-size:20px; font-weight:700; letter-spacing:0.3px;">Meddata</span>
                            <span style="color:#9fb3c8; font-size:13px; display:block; margin-top:2px;">Medicine Stock &amp; Expiry Tracker</span>
                        </td>
                    </tr>
                    <!-- Body -->
                    <tr>
                        <td style="padding:32px;">
                            @yield('content')
                        </td>
                    </tr>
                    <!-- Footer -->
                    <tr>
                        <td style="padding:20px 32px; border-top:1px solid #eceff1; background-color:#fafbfc;">
                            <p style="margin:0; color:#8a97a3; font-size:12px; line-height:18px;">
                                You are receiving this email because an action occurred on your Meddata account.
                                If this wasn't you, please contact {{ $supportEmail ?? 'support@meddata.app' }}.
                            </p>
                            <p style="margin:8px 0 0; color:#b0bac3; font-size:12px;">
                                &copy; {{ now()->year }} Meddata. All rights reserved.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
