<?php

namespace Tests\Feature;

use App\Models\ApiToken;
use App\Models\Entitlement;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
    }

    private function register(array $overrides = []): TestResponse
    {
        return $this->postJson('/api/v1/auth/register', array_merge([
            'name' => 'Test User',
            'email' => 'user@example.com',
            'password' => 'secret123',
        ], $overrides));
    }

    public function test_register_returns_token_user_and_premium_trial_entitlement(): void
    {
        $res = $this->register()
            ->assertCreated()
            ->assertJsonStructure([
                'token',
                'user' => ['id', 'name', 'email', 'phone'],
                'entitlement' => ['premium', 'status', 'source', 'trial_ends_at', 'days_left', 'expiry_time', 'product_id'],
            ])
            ->assertJsonPath('user.email', 'user@example.com')
            ->assertJsonPath('entitlement.premium', true)
            ->assertJsonPath('entitlement.source', 'trial');

        $this->assertNotEmpty($res->json('token'));
        $this->assertDatabaseHas('users', ['email' => 'user@example.com', 'is_admin' => 0]);
    }

    public function test_register_duplicate_email_returns_422(): void
    {
        $this->register()->assertCreated();
        $this->register()->assertStatus(422);
    }

    public function test_login_success_and_wrong_password(): void
    {
        $this->register();

        $this->postJson('/api/v1/auth/login', [
            'email' => 'user@example.com',
            'password' => 'secret123',
        ])
            ->assertOk()
            ->assertJsonStructure(['token', 'user', 'entitlement'])
            ->assertJsonPath('user.email', 'user@example.com');

        $this->postJson('/api/v1/auth/login', [
            'email' => 'user@example.com',
            'password' => 'wrongpass',
        ])
            ->assertStatus(422)
            ->assertJsonPath('message', 'Invalid credentials');
    }

    public function test_me_with_token_returns_user(): void
    {
        $token = $this->register()->json('token');

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/auth/me')
            ->assertOk()
            ->assertJsonPath('user.email', 'user@example.com')
            ->assertJsonPath('entitlement.premium', true);
    }

    /** The app ties the data on a device to user.id, so it must not change with the email. */
    public function test_user_id_is_stable_across_login_me_and_an_email_change(): void
    {
        $id = $this->register()->json('user.id');
        $this->assertIsInt($id);

        $token = $this->postJson('/api/v1/auth/login', [
            'email' => 'user@example.com',
            'password' => 'secret123',
        ])->assertOk()->assertJsonPath('user.id', $id)->json('token');

        $this->withHeader('Authorization', "Bearer {$token}")
            ->patchJson('/api/v1/auth/profile', ['email' => 'new@example.com'])
            ->assertOk()
            ->assertJsonPath('user.id', $id)
            ->assertJsonPath('user.email', 'new@example.com');

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/auth/me')
            ->assertOk()
            ->assertJsonPath('user.id', $id)
            ->assertJsonPath('user.email', 'new@example.com');

        $this->postJson('/api/v1/auth/login', [
            'email' => 'new@example.com',
            'password' => 'secret123',
        ])->assertOk()->assertJsonPath('user.id', $id);
    }

    public function test_me_without_token_returns_401(): void
    {
        $this->getJson('/api/v1/auth/me')
            ->assertStatus(401)
            ->assertJsonPath('message', 'Unauthenticated');
    }

    public function test_logout_revokes_token(): void
    {
        $token = $this->register()->json('token');

        $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/v1/auth/logout')
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->assertDatabaseMissing('api_tokens', [
            'token' => ApiToken::hashToken($token),
        ]);

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/auth/me')
            ->assertStatus(401);
    }

    public function test_forgot_password_returns_ok_with_dev_code_in_testing_env(): void
    {
        $this->register();

        $res = $this->postJson('/api/v1/auth/forgot-password', [
            'email' => 'user@example.com',
        ])
            ->assertOk()
            ->assertJsonPath('ok', true);

        // dev_code is echoed only in the local/testing environments (phpunit runs as 'testing').
        $this->assertMatchesRegularExpression('/^\d{6}$/', (string) $res->json('dev_code'));

        $this->assertDatabaseHas('password_reset_codes', [
            'email' => 'user@example.com',
            'code' => $res->json('dev_code'),
        ]);
    }

    public function test_forgot_password_never_echoes_the_code_outside_local_and_testing(): void
    {
        $this->register();
        config(['app.debug' => true]); // APP_DEBUG alone must not expose the code

        foreach (['production', 'staging'] as $env) {
            $this->app['env'] = $env;
            $this->postJson('/api/v1/auth/forgot-password', ['email' => 'user@example.com'])
                ->assertOk()
                ->assertJsonPath('ok', true)
                ->assertJsonMissingPath('dev_code');
        }

        $this->assertDatabaseHas('password_reset_codes', ['email' => 'user@example.com']);
    }

    public function test_signing_in_with_another_users_device_id_leaves_their_plan_alone(): void
    {
        // A pays yearly; the app last reported A's phone as dev-A.
        $owner = User::factory()->create(['is_admin' => false]);
        $paid = Entitlement::create([
            'user_id' => $owner->id,
            'device_id' => 'dev-A',
            'product_id' => 'premium_yearly',
            'source' => 'razorpay',
            'status' => 'active',
            'is_premium' => true,
            'expiry_time' => now()->addYear(),
        ]);

        // B signs up and signs in sending A's device id: B gets B's own trial.
        $token = $this->register(['email' => 'b@example.com', 'device_id' => 'dev-A'])
            ->assertCreated()
            ->assertJsonPath('entitlement.source', 'trial')
            ->json('token');
        $this->postJson('/api/v1/auth/login', [
            'email' => 'b@example.com',
            'password' => 'secret123',
            'device_id' => 'dev-A',
        ])
            ->assertOk()
            ->assertJsonPath('entitlement.source', 'trial')
            ->assertJsonPath('entitlement.expiry_time', null);
        $this->withToken($token)->getJson('/api/v1/entitlement?device_id=dev-A')
            ->assertOk()
            ->assertJsonPath('source', 'trial');

        // A's paid plan is neither taken over nor stripped.
        $paid->refresh();
        $this->assertSame($owner->id, $paid->user_id);
        $this->assertSame('razorpay', $paid->source);
        $this->assertTrue($paid->isActivePaid());
        $this->assertSame(1, Entitlement::where('source', 'razorpay')->count());
        $this->withToken($owner->issueToken('t'))->getJson('/api/v1/auth/me')
            ->assertOk()
            ->assertJsonPath('entitlement.premium', true)
            ->assertJsonPath('entitlement.source', 'razorpay');
    }

    public function test_forgot_password_generic_for_unknown_email(): void
    {
        $this->postJson('/api/v1/auth/forgot-password', [
            'email' => 'nobody@example.com',
        ])
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->assertDatabaseMissing('password_reset_codes', [
            'email' => 'nobody@example.com',
        ]);
    }

    public function test_reset_password_with_correct_code_changes_password(): void
    {
        $this->register();

        $code = $this->postJson('/api/v1/auth/forgot-password', [
            'email' => 'user@example.com',
        ])->json('dev_code');

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => 'user@example.com',
            'code' => $code,
            'password' => 'newsecret456',
        ])
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->assertTrue(Hash::check('newsecret456', User::where('email', 'user@example.com')->first()->password));

        // Login works with the new password.
        $this->postJson('/api/v1/auth/login', [
            'email' => 'user@example.com',
            'password' => 'newsecret456',
        ])->assertOk();

        // Old password no longer works.
        $this->postJson('/api/v1/auth/login', [
            'email' => 'user@example.com',
            'password' => 'secret123',
        ])->assertStatus(422);
    }

    public function test_reset_password_with_wrong_code_returns_422(): void
    {
        $this->register();

        $this->postJson('/api/v1/auth/forgot-password', ['email' => 'user@example.com']);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => 'user@example.com',
            'code' => '000000',
            'password' => 'newsecret456',
        ])
            ->assertStatus(422)
            ->assertJsonPath('message', 'Invalid or expired code');
    }

    public function test_avatar_upload_replace_serve_and_delete(): void
    {
        Storage::fake('local');
        $token = $this->register()->json('token');
        $auth = ['Authorization' => "Bearer {$token}", 'Accept' => 'application/json'];

        $this->withHeaders($auth)->getJson('/api/v1/auth/me')
            ->assertJsonPath('user.avatar_url', null);

        $first = $this->withHeaders($auth)->post('/api/v1/auth/avatar', [
            'avatar' => UploadedFile::fake()->image('me.jpg', 300, 300),
        ])->assertOk();
        $firstUrl = $first->json('user.avatar_url');
        $this->assertNotNull($firstUrl);
        $firstPath = User::where('email', 'user@example.com')->value('avatar_path');
        Storage::disk('local')->assertExists($firstPath);

        $this->get(parse_url($firstUrl, PHP_URL_PATH))->assertOk();

        // Replacing removes the previous file.
        $this->withHeaders($auth)->post('/api/v1/auth/avatar', [
            'avatar' => UploadedFile::fake()->image('new.png', 200, 200),
        ])->assertOk();
        Storage::disk('local')->assertMissing($firstPath);

        $this->withHeaders($auth)->deleteJson('/api/v1/auth/avatar')
            ->assertOk()
            ->assertJsonPath('user.avatar_url', null);
        $this->assertSame([], Storage::disk('local')->files('avatars'));
    }

    public function test_avatar_rejects_non_images_and_requires_auth(): void
    {
        Storage::fake('local');
        $token = $this->register()->json('token');

        $this->withHeaders(['Authorization' => "Bearer {$token}", 'Accept' => 'application/json'])
            ->post('/api/v1/auth/avatar', [
                'avatar' => UploadedFile::fake()->create('doc.pdf', 10, 'application/pdf'),
            ])
            ->assertStatus(422);

        $this->flushHeaders()
            ->withHeaders(['Accept' => 'application/json'])
            ->post('/api/v1/auth/avatar', ['avatar' => UploadedFile::fake()->image('me.jpg')])
            ->assertStatus(401);

        $this->get('/api/v1/avatars/1_nope.jpg')->assertNotFound();
        $this->get('/api/v1/avatars/..%2F..%2F.env')->assertNotFound();
    }
}
