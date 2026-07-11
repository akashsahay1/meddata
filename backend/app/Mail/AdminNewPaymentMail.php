<?php

namespace App\Mail;

use App\Models\AppSetting;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class AdminNewPaymentMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public User $user,
        public string $planName,
        public float $amount,
        public string $currency,
        public string $paymentId,
        public bool $isRenewal = false,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: ($this->isRenewal ? 'Renewal' : 'New payment')
                . ': ' . $this->currency . ' ' . number_format($this->amount, 2),
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.admin.new_payment',
            with: [
                'supportEmail' => AppSetting::get('support_email', 'support@meddata.app'),
            ],
        );
    }
}
