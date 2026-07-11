<?php

namespace App\Mail;

use App\Models\AppSetting;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class PasswordResetMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $code,
        public int $ttlMinutes = 15,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Your Meddata password reset code');
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.password_reset',
            with: [
                'supportEmail' => AppSetting::get('support_email', 'support@meddata.app'),
            ],
        );
    }
}
