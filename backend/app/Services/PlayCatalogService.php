<?php

namespace App\Services;

/**
 * Reads the subscription/product catalog from Google Play so it can be mirrored
 * into the local `plans` table. Google Play does NOT push catalog changes to the
 * server, so we pull them on demand (button / scheduled command).
 *
 * Like GooglePlayVerifier, this has a safe local-dev fallback so the flow works
 * end-to-end before the Play Developer API service account is configured.
 *
 * To enable the real pull:
 *   1. Service account with Google Play Developer API access.
 *   2. Set GOOGLE_PLAY_CREDENTIALS (path to the JSON key) in .env.
 *   3. Implement listFromGoogle() using the Android Publisher API:
 *      - Subscriptions: monetization.subscriptions.list (+ basePlans/prices)
 *      - One-time products: inappproducts.list
 */
class PlayCatalogService
{
    /**
     * @return array<int, array{product_id:string,name:string,billing_period:string,price:float,currency:string}>
     */
    public function list(): array
    {
        $credentials = config('services.google_play.credentials');

        if ($credentials && file_exists($credentials)) {
            return $this->listFromGoogle();
        }

        return $this->fallbackCatalog();
    }

    /** Whether real Google Play data (vs. the dev fallback) is being used. */
    public function isLive(): bool
    {
        $credentials = config('services.google_play.credentials');
        return (bool) ($credentials && file_exists($credentials));
    }

    /**
     * Dev fallback: the product ids we expect in Play, so the sync is testable
     * without credentials. Prices here are placeholders — real prices always
     * come from Play at runtime in the app.
     */
    protected function fallbackCatalog(): array
    {
        return [
            ['product_id' => 'premium_monthly', 'name' => 'Monthly Plan', 'billing_period' => 'monthly', 'price' => 99, 'currency' => 'INR'],
            ['product_id' => 'premium_yearly', 'name' => 'Yearly Plan', 'billing_period' => 'yearly', 'price' => 999, 'currency' => 'INR'],
            ['product_id' => 'premium_lifetime', 'name' => 'Lifetime', 'billing_period' => 'lifetime', 'price' => 2499, 'currency' => 'INR'],
        ];
    }

    /**
     * Real pull from the Google Play Developer API. Left as a clearly-marked
     * integration point (needs the service-account credentials).
     *
     * @return array<int, array{product_id:string,name:string,billing_period:string,price:float,currency:string}>
     */
    protected function listFromGoogle(): array
    {
        // Pseudocode:
        // $client = new \Google\Client();
        // $client->setAuthConfig(config('services.google_play.credentials'));
        // $client->addScope(\Google\Service\AndroidPublisher::ANDROIDPUBLISHER);
        // $publisher = new \Google\Service\AndroidPublisher($client);
        // $package = config('services.google_play.package_name');
        // $subs = $publisher->monetization_subscriptions->listMonetizationSubscriptions($package);
        // foreach ($subs->getSubscriptions() as $s) { map productId + basePlan price/period }
        //
        // Return the same shape as fallbackCatalog().

        return $this->fallbackCatalog();
    }
}
