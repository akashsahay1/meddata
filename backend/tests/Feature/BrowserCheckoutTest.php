<?php

namespace Tests\Feature;

use App\Models\Entitlement;
use App\Models\Payment;
use App\Models\Plan;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class BrowserCheckoutTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        config(['services.razorpay.key_id' => 'rzp_test_x', 'services.razorpay.key_secret' => 'sekret']);
        Http::fake(['api.razorpay.com/*' => Http::response(['id' => 'order_TEST123', 'amount' => 49900, 'currency' => 'INR'])]);
        $this->user = User::factory()->create(['is_admin' => false]);
    }

    private function createOrder(): string
    {
        $plan = Plan::where('product_id', 'premium_yearly')->firstOrFail();

        return $this->withToken($this->user->issueToken('t'))
            ->postJson('/api/v1/order/create', ['plan_id' => $plan->id])
            ->assertOk()
            ->json('order_id');
    }

    private function sign(string $order, string $payment): string
    {
        return hash_hmac('sha256', $order.'|'.$payment, 'sekret');
    }

    public function test_checkout_page_opens_for_an_unpaid_order(): void
    {
        $order = $this->createOrder();
        $this->get('/api/v1/pay/'.$order)
            ->assertOk()
            ->assertSee('checkout.razorpay.com', false)
            ->assertSee('"order_id":"'.$order.'"', false)
            ->assertSee('"redirect":true', false);

        $this->get('/api/v1/pay/order_nope')->assertOk()->assertSee('Order not found.');
    }

    public function test_verified_callback_activates_premium_once(): void
    {
        $order = $this->createOrder();
        $payload = [
            'razorpay_order_id' => $order,
            'razorpay_payment_id' => 'pay_1',
            'razorpay_signature' => $this->sign($order, 'pay_1'),
        ];

        $this->post('/api/v1/pay/complete', $payload)->assertOk()->assertSee('Payment successful');
        $this->post('/api/v1/pay/complete', $payload)->assertOk()->assertSee('Payment successful');

        $this->assertSame('paid', Payment::where('razorpay_order_id', $order)->value('status'));
        $ent = Entitlement::where('user_id', $this->user->id)->sole();
        $this->assertTrue($ent->isActivePaid());
        $this->assertSame('razorpay', $ent->source);

        // The page for an already-paid order says so instead of charging again.
        $this->get('/api/v1/pay/'.$order)->assertSee('already paid');
    }

    public function test_bad_signature_or_cancel_does_not_activate(): void
    {
        $order = $this->createOrder();

        $this->post('/api/v1/pay/complete', [
            'razorpay_order_id' => $order,
            'razorpay_payment_id' => 'pay_2',
            'razorpay_signature' => 'forged',
        ])->assertOk()->assertSee('could not verify');

        $this->post('/api/v1/pay/complete', [
            'error' => ['code' => 'BAD_REQUEST_ERROR', 'description' => 'Payment cancelled by user'],
        ])->assertOk()->assertSee('Payment cancelled by user')->assertDontSee('BAD_REQUEST_ERROR');

        $this->assertSame('failed', Payment::where('razorpay_order_id', $order)->value('status'));
        $this->assertFalse((bool) Entitlement::where('user_id', $this->user->id)->first()?->isActivePaid());
    }
}
