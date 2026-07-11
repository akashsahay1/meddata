<?php

namespace App\Mail;

use App\Models\AppSetting;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class WelcomeMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * @param  array<string,mixed>|null  $entitlement
     */
    public function __construct(
        public User $user,
        public ?array $entitlement = null,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Welcome to Meddata');
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.welcome',
            with: [
                'supportEmail' => AppSetting::get('support_email', 'support@meddata.app'),
            ],
        );
    }
}
