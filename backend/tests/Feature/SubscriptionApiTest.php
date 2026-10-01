<?php

namespace Tests\Feature;

use App\Models\Coupon;
use App\Models\Entitlement;
use App\Models\Plan;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SubscriptionApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
    }

    private function yearlyPlan(): Plan
    {
        return Plan::where('product_id', 'premium_yearly')->firstOrFail();
    }

    private function authHeaders(?User $user = null): array
    {
        $user ??= User::factory()->create(['is_admin' => false]);

        return ['Authorization' => 'Bearer '.$user->issueToken('test')];
    }

    public function test_config_returns_trial_days_and_razorpay_key(): void
    {
        $this->getJson('/api/v1/config')
            ->assertOk()
            ->assertJsonPath('trial_days', 7)
            ->assertJsonPath('razorpay_key_id', '')
            ->assertJsonStructure(['plans' => [['id', 'product_id', 'price']]]);
    }

    public function test_coupon_validate_percentage(): void
    {
        $plan = $this->yearlyPlan(); // ₹999
        $this->postJson('/api/v1/coupon/validate', [
            'code' => 'WELCOME20',
            'plan_id' => $plan->id,
        ], $this->authHeaders())
            ->assertOk()
            ->assertJsonPath('valid', true)
            ->assertJsonPath('type', 'percentage')
            ->assertJsonPath('discount', 199.8)
            ->assertJsonPath('final_amount', 799.2);
    }

    public function test_coupon_validate_flat(): void
    {
        $plan = $this->yearlyPlan(); // ₹999
        $this->postJson('/api/v1/coupon/validate', [
            'code' => 'FLAT100',
            'plan_id' => $plan->id,
        ], $this->authHeaders())
            ->assertOk()
            ->assertJsonPath('valid', true)
            ->assertJsonPath('type', 'flat')
            ->assertJsonPath('discount', 100)
            ->assertJsonPath('final_amount', 899);
    }

    public function test_coupon_validate_rejects_inactive_or_below_min(): void
    {
        $plan = $this->yearlyPlan();
        Coupon::create([
            'code' => 'BIGSPEND',
            'type' => 'flat',
            'value' => 50,
            'min_amount' => 5000,
            'is_active' => true,
        ]);

        $this->postJson('/api/v1/coupon/validate', [
            'code' => 'BIGSPEND',
            'plan_id' => $plan->id,
        ], $this->authHeaders())
            ->assertOk()
            ->assertJsonPath('valid', false);
    }

    public function test_trial_register_sets_seven_day_window(): void
    {
        $headers = $this->authHeaders();

        $res = $this->postJson('/api/v1/device/trial', ['device_id' => 'dev-trial'], $headers)
            ->assertOk()
            ->assertJsonPath('is_trial_active', true)
            ->assertJsonPath('days_left', 7);

        $ent = Entitlement::where('device_id', 'dev-trial')->firstOrFail();
        $this->assertNotNull($ent->trial_started_at);
        $this->assertNotNull($ent->trial_ends_at);
        $this->assertSame('trial', $ent->source);
        $this->assertEqualsWithDelta(7, $ent->trial_started_at->diffInDays($ent->trial_ends_at), 0.01);
    }

    public function test_trial_register_is_idempotent(): void
    {
        $user = User::factory()->create(['is_admin' => false]);
        $headers = $this->authHeaders($user);

        $first = $this->postJson('/api/v1/device/trial', ['device_id' => 'dev-idem'], $headers)->json('trial_ends_at');
        $second = $this->postJson('/api/v1/device/trial', ['device_id' => 'dev-idem'], $headers)->json('trial_ends_at');
        $this->assertSame($first, $second);
        $this->assertSame(1, Entitlement::where('user_id', $user->id)->count());
    }

    public function test_entitlement_shows_premium_during_trial(): void
    {
        $headers = $this->authHeaders();
        $this->postJson('/api/v1/device/trial', ['device_id' => 'dev-ent'], $headers);

        $this->getJson('/api/v1/entitlement?device_id=dev-ent', $headers)
            ->assertOk()
            ->assertJsonPath('premium', true)
            ->assertJsonPath('source', 'trial')
            ->assertJsonPath('status', 'active');
    }

    public function test_order_create_returns_order_id_dev_fallback(): void
    {
        $plan = $this->yearlyPlan();
        $res = $this->postJson('/api/v1/order/create', [
            'device_id' => 'dev-order',
            'plan_id' => $plan->id,
            'coupon_code' => 'WELCOME20',
        ], $this->authHeaders())
            ->assertOk()
            ->assertJsonPath('final_amount_rupees', 799.2)
            ->assertJsonPath('amount', 79920) // paise
            ->assertJsonStructure(['order_id', 'amount', 'currency', 'key_id']);

        $this->assertStringStartsWith('order_dev_', $res->json('order_id'));
        $this->assertDatabaseHas('payments', [
            'device_id' => 'dev-order',
            'status' => 'created',
        ]);
    }

    public function test_order_create_returns_502_when_razorpay_rejects_order(): void
    {
        config(['services.razorpay.key_id' => 'rzp_test_x', 'services.razorpay.key_secret' => 'bad']);
        Http::fake(['api.razorpay.com/*' => Http::response(
            ['error' => ['code' => 'BAD_REQUEST_ERROR', 'description' => 'Authentication failed']], 401
        )]);

        $this->postJson('/api/v1/order/create', [
            'plan_id' => $this->yearlyPlan()->id,
        ], $this->authHeaders())->assertStatus(502);

        $this->assertDatabaseCount('payments', 0);
    }

    public function test_order_create_returns_502_when_key_secret_missing(): void
    {
        config(['services.razorpay.key_id' => 'rzp_test_x', 'services.razorpay.key_secret' => '']);

        $this->postJson('/api/v1/order/create', [
            'plan_id' => $this->yearlyPlan()->id,
        ], $this->authHeaders())->assertStatus(502);
    }

    public function test_payment_verify_activates_entitlement_dev_fallback(): void
    {
        $plan = $this->yearlyPlan();
        $headers = $this->authHeaders();
        $order = $this->postJson('/api/v1/order/create', [
            'device_id' => 'dev-pay',
            'plan_id' => $plan->id,
        ], $headers)->json();

        $this->postJson('/api/v1/payment/verify', [
            'device_id' => 'dev-pay',
            'razorpay_order_id' => $order['order_id'],
            'razorpay_payment_id' => 'pay_dev1',
            'razorpay_signature' => 'anything',
            'plan_id' => $plan->id,
        ], $headers)
            ->assertOk()
            ->assertJsonPath('premium', true)
            ->assertJsonPath('status', 'active');

        $ent = Entitlement::where('device_id', 'dev-pay')->firstOrFail();
        $this->assertSame('razorpay', $ent->source);
        $this->assertTrue($ent->is_premium);
        $this->assertTrue($ent->expiry_time->isFuture());

        $this->assertDatabaseHas('payments', [
            'razorpay_order_id' => $order['order_id'],
            'status' => 'paid',
            'razorpay_payment_id' => 'pay_dev1',
        ]);
    }

    public function test_payment_verify_increments_coupon_usage(): void
    {
        $plan = $this->yearlyPlan();
        $headers = $this->authHeaders();
        $before = Coupon::where('code', 'WELCOME20')->firstOrFail()->used_count;

        $order = $this->postJson('/api/v1/order/create', [
            'device_id' => 'dev-coupon',
            'plan_id' => $plan->id,
            'coupon_code' => 'WELCOME20',
        ], $headers)->json();

        $this->postJson('/api/v1/payment/verify', [
            'device_id' => 'dev-coupon',
            'razorpay_order_id' => $order['order_id'],
            'razorpay_payment_id' => 'pay_dev2',
            'razorpay_signature' => 'x',
            'plan_id' => $plan->id,
            'coupon_code' => 'WELCOME20',
        ], $headers)->assertOk();

        $this->assertSame($before + 1, Coupon::where('code', 'WELCOME20')->firstOrFail()->used_count);
    }

    public function test_lifetime_plan_has_no_expiry(): void
    {
        $plan = Plan::where('product_id', 'premium_lifetime')->firstOrFail();
        $headers = $this->authHeaders();
        $order = $this->postJson('/api/v1/order/create', [
            'device_id' => 'dev-life',
            'plan_id' => $plan->id,
        ], $headers)->json();

        $this->postJson('/api/v1/payment/verify', [
            'device_id' => 'dev-life',
            'razorpay_order_id' => $order['order_id'],
            'razorpay_payment_id' => 'pay_life',
            'razorpay_signature' => 'x',
            'plan_id' => $plan->id,
        ], $headers)
            ->assertOk()
            ->assertJsonPath('premium', true);

        $ent = Entitlement::where('device_id', 'dev-life')->firstOrFail();
        $this->assertNull($ent->expiry_time);
        $this->assertTrue($ent->isActivePaid());
    }
}
