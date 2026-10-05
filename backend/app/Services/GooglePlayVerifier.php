<?php

namespace App\Services;

use Carbon\Carbon;

/**
 * Verifies Google Play purchases. In production this calls the Google Play
 * Developer API using a service account. Here we provide the structure and a
 * safe local-dev fallback so the flow is fully wired end to end.
 *
 * To enable real verification:
 *   1. Create a service account in Google Cloud with Play Developer API access.
 *   2. Put the JSON key path in config (GOOGLE_PLAY_CREDENTIALS).
 *   3. Implement the API call in verifyWithGoogle().
 */
class GooglePlayVerifier
{
    /**
     * @return array{valid: bool, expiry: ?Carbon, status: string}
     */
    public function verify(string $productId, string $purchaseToken): array
    {
        $credentials = config('services.google_play.credentials');

        if ($credentials && file_exists($credentials)) {
            return $this->verifyWithGoogle($productId, $purchaseToken);
        }

        // Fail CLOSED: without service-account credentials we cannot verify a
        // real purchase, so never grant premium. Only local dev and the test
        // suite may accept it (any other APP_ENV, e.g. staging, is refused).
        if (! app()->environment('local', 'testing')) {
            return ['valid' => false, 'expiry' => null, 'status' => 'unverified'];
        }

        // Local-dev fallback: accept the purchase and grant an expiry based on
        // the plan period so the app can be tested without Play credentials.
        return [
            'valid' => true,
            'expiry' => $this->fallbackExpiry($productId),
            'status' => 'active',
        ];
    }

    protected function fallbackExpiry(string $productId): ?Carbon
    {
        if (str_contains($productId, 'lifetime')) {
            return null; // no expiry
        }
        if (str_contains($productId, 'yearly')) {
            return Carbon::now()->addYear();
        }
        return Carbon::now()->addMonth();
    }

    /**
     * Real verification against the Google Play Developer API.
     * Left as a clearly-marked integration point.
     *
     * @return array{valid: bool, expiry: ?Carbon, status: string}
     */
    protected function verifyWithGoogle(string $productId, string $purchaseToken): array
    {
        // Pseudocode for the real integration:
        // $client = new \Google\Client();
        // $client->setAuthConfig(config('services.google_play.credentials'));
        // $client->addScope(\Google\Service\AndroidPublisher::ANDROIDPUBLISHER);
        // $service = new \Google\Service\AndroidPublisher($client);
        // $sub = $service->purchases_subscriptions->get($packageName, $productId, $purchaseToken);
        // $expiry = Carbon::createFromTimestampMs($sub->getExpiryTimeMillis());
        // return ['valid' => true, 'expiry' => $expiry, 'status' => $expiry->isFuture() ? 'active' : 'expired'];

        // Not implemented yet: until it is, configured credentials must not
        // turn any client-supplied token into premium. Fail closed.
        return ['valid' => false, 'expiry' => null, 'status' => 'unverified'];
    }
}
