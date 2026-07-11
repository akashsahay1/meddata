<?php

namespace App\Mail;

use App\Models\AppSetting;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class AdminNewUserMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(public User $user)
    {
    }

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'New Meddata signup: ' . $this->user->email);
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.admin.new_user',
            with: [
                'supportEmail' => AppSetting::get('support_email', 'support@meddata.app'),
            ],
        );
    }
}
