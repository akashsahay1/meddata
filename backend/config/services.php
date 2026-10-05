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

    // Claude API, used by the queued AI purchase-invoice reader. Without a
    // key, scans fail with a clear "not configured" status.
    'anthropic' => [
        'key' => env('ANTHROPIC_API_KEY'),
        'model' => env('ANTHROPIC_MODEL', 'claude-opus-5-5'),
        // low|medium|high|xhigh|max; empty = leave out (models without effort).
        'effort' => env('ANTHROPIC_EFFORT', 'medium'),
        // Thinking counts towards this, so keep room for a long invoice.
        'max_tokens' => (int) env('ANTHROPIC_MAX_TOKENS', 16000),
        // Seconds for one API call; the job's own timeout is a bit longer.
        'timeout' => (int) env('ANTHROPIC_TIMEOUT', 240),
        // 'default' = server-side refusal fallback to the model Anthropic
        // recommends (sent only for models that support it); 'off' disables.
        'fallbacks' => env('ANTHROPIC_FALLBACKS', 'default'),
        'base_url' => env('ANTHROPIC_BASE_URL', 'https://api.anthropic.com'),
    ],

];
