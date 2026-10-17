<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'google_play' => [
        // Path to the service-account JSON with Play Developer API access.
        'credentials' => env('GOOGLE_PLAY_CREDENTIALS'),
        'package_name' => env('GOOGLE_PLAY_PACKAGE', 'com.medstock.med_stock'),
    ],

    'razorpay' => [
        'key_id' => env('RAZORPAY_KEY_ID'),
        'key_secret' => env('RAZORPAY_KEY_SECRET'),
    ],

    // Groq (OpenAI-compatible API), used by the queued AI purchase-invoice
    // reader. Without a key, scans fail with a clear "not configured" status.
    'groq' => [
        'key' => env('GROQ_API_KEY'),
        // A vision model with strict JSON-schema output (at most 3 images).
        'model' => env('GROQ_MODEL', 'qwen/qwen3.8-27b'),
        // Room for a long invoice; the model allows up to 16384.
        'max_tokens' => (int) env('GROQ_MAX_TOKENS', 8192),
        // Reads the text inside a PDF made by billing software (exact, cheap).
        'text_model' => env('GROQ_TEXT_MODEL', 'openai/gpt-oss-120b'),
        // A 48-line bill took ~6,100 reply tokens.
        'text_max_tokens' => (int) env('GROQ_TEXT_MAX_TOKENS', 16384),
        // Seconds for one API call; the job's own timeout is longer.
        'timeout' => (int) env('GROQ_TIMEOUT', 120),
        'base_url' => env('GROQ_BASE_URL', 'https://api.groq.com/openai/v1'),
    ],

];
