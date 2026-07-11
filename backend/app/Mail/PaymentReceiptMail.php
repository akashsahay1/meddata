<?php

namespace App\Mail;

use App\Models\AppSetting;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class PaymentReceiptMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public User $user,
        public string $planName,
        public float $amount,
        public string $currency,
        public string $paymentId,
        public ?string $expiry,
        public bool $isRenewal = false,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: $this->isRenewal
                ? 'Your Meddata subscription was renewed'
                : 'Your Meddata payment receipt',
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.payment_receipt',
            with: [
                'supportEmail' => AppSetting::get('support_email', 'support@meddata.app'),
            ],
        );
    }
}
