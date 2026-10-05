<?php

namespace Tests\Feature;

use App\Models\Entitlement;
use App\Models\Payment;
use App\Models\Plan;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Premium is only granted for a payment Razorpay really signed: the no-keys
 * dev fallback exists in the local/testing environments only, and a verified
 * order activates once.
 */
class PaymentSecurityTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        $this->user = User::factory()->create(['is_admin' => false]);
        // Independent of any keys in the developer's .env.
        config(['services.razorpay.key_id' => '', 'services.razorpay.key_secret' => '']);
    }

    /** Behave like a live server; APP_DEBUG must not matter. */
    private function asLiveServer(string $env = 'production'): void
    {
        $this->app['env'] = $env;
        config(['app.debug' => true]);
    }

    private function withKeys(): void
    {
        config(['services.razorpay.key_id' => 'rzp_live_x', 'services.razorpay.key_secret' => 'sekret']);
        Http::fake(['api.razorpay.com/*' => Http::response(['id' => 'order_LIVE1', 'amount' => 9900, 'currency' => 'INR'])]);
    }

    private function monthlyPlan(): Plan
    {
        return Plan::where('product_id', 'premium_monthly')->firstOrFail();
    }

    private function createOrder(): TestResponse
    {
        return $this->withToken($this->user->issueToken('t'))
            ->postJson('/api/v1/order/create', ['plan_id' => $this->monthlyPlan()->id]);
    }

    private function verify(string $order, string $payment, string $signature): TestResponse
    {
        return $this->withToken($this->user->issueToken('t'))->postJson('/api/v1/payment/verify', [
            'razorpay_order_id' => $order,
            'razorpay_payment_id' => $payment,
            'razorpay_signature' => $signature,
        ]);
    }

    private function sign(string $order, string $payment): string
    {
        return hash_hmac('sha256', $order.'|'.$payment, 'sekret');
    }

    private function entitlement(): ?Entitlement
    {
        return Entitlement::where('user_id', $this->user->id)->first();
    }

    private function hasPaidPlan(): bool
    {
        return (bool) $this->entitlement()?->isActivePaid();
    }

    public function test_production_without_keys_never_grants_premium(): void
    {
        // An unpaid order from before the keys were removed.
        $order = Payment::create([
            'device_id' => 'dev-1',
            'user_id' => $this->user->id,
            'plan_id' => $this->monthlyPlan()->id,
            'amount' => 99,
            'currency' => 'INR',
            'razorpay_order_id' => 'order_dev_old',
            'status' => 'created',
        ]);

        // Any environment but local/testing, not just one named 'production'.
        foreach (['production', 'staging'] as $env) {
            $this->asLiveServer($env);

            // No new order is handed out...
            $this->createOrder()
                ->assertStatus(503)
                ->assertJsonPath('message', 'Payments are not available right now.');

            // ...and an unsigned "payment" is refused, in-app and in the browser.
            $this->verify('order_dev_old', 'pay_dev_1', 'dev')
                ->assertStatus(422)
                ->assertJsonPath('premium', false);
            $this->post('/api/v1/pay/complete', [
                'razorpay_order_id' => 'order_dev_old',
                'razorpay_payment_id' => 'pay_dev_1',
                'razorpay_signature' => 'dev',
            ])->assertOk()->assertSee('could not verify');
        }

        $this->assertSame(1, Payment::count());
        $this->assertNotSame('paid', $order->fresh()->status);
        $this->assertFalse($this->hasPaidPlan());
        $this->withToken($this->user->issueToken('t'))->getJson('/api/v1/auth/me')
            ->assertOk()
            ->assertJsonPath('entitlement.premium', false);
    }

    public function test_production_with_keys_rejects_a_bad_signature(): void
    {
        $this->asLiveServer();
        $this->withKeys();
        $order = $this->createOrder()->assertOk()->assertJsonPath('key_id', 'rzp_live_x')->json('order_id');

        foreach (['', 'dev', 'forged', $this->sign($order, 'pay_other')] as $bad) {
            $this->verify($order, 'pay_1', $bad)
                ->assertStatus(422)
                ->assertJsonPath('premium', false);
        }
        $this->assertFalse($this->hasPaidPlan());

        // The genuine signature still activates the plan.
        $this->verify($order, 'pay_1', $this->sign($order, 'pay_1'))
            ->assertOk()
            ->assertJsonPath('premium', true);
        $this->assertTrue($this->hasPaidPlan());
    }

    public function test_replaying_a_verified_payment_does_not_extend_the_plan(): void
    {
        $this->withKeys();
        $order = $this->createOrder()->assertOk()->json('order_id');
        $signature = $this->sign($order, 'pay_1');

        $this->verify($order, 'pay_1', $signature)->assertOk()->assertJsonPath('premium', true);
        $expiry = $this->entitlement()->expiry_time->toIso8601String();

        // A retry (say the first response was lost) changes nothing.
        $this->travel(20)->days();
        $this->verify($order, 'pay_1', $signature)->assertOk()->assertJsonPath('premium', true);
        $this->assertSame($expiry, $this->entitlement()->expiry_time->toIso8601String());

        // Replayed once the month is over, the same order buys nothing.
        $this->travel(15)->days();
        $this->verify($order, 'pay_1', $signature)
            ->assertOk()
            ->assertJsonPath('premium', false)
            ->assertJsonPath('status', 'expired');
        $this->post('/api/v1/pay/complete', [
            'razorpay_order_id' => $order,
            'razorpay_payment_id' => 'pay_1',
            'razorpay_signature' => $signature,
        ])->assertOk()->assertSee('already used');

        $this->assertSame($expiry, $this->entitlement()->expiry_time->toIso8601String());
        $this->assertFalse($this->hasPaidPlan());
    }

    public function test_google_play_purchase_is_never_trusted_unverified(): void
    {
        $purchase = ['product_id' => 'premium_lifetime', 'purchase_token' => 'made-up'];
        $credentials = tempnam(sys_get_temp_dir(), 'play');

        try {
            // Credentials present, but real verification isn't implemented.
            config(['services.google_play.credentials' => $credentials]);
            $this->withToken($this->user->issueToken('t'))
                ->postJson('/api/v1/purchase/verify', $purchase)
                ->assertStatus(422)
                ->assertJsonPath('premium', false);

            // No credentials outside local/testing.
            config(['services.google_play.credentials' => null]);
            $this->asLiveServer();
            $this->withToken($this->user->issueToken('t'))
                ->postJson('/api/v1/purchase/verify', $purchase)
                ->assertStatus(422)
                ->assertJsonPath('premium', false);
        } finally {
            unlink($credentials);
        }

        $this->assertFalse($this->hasPaidPlan());
    }
}
