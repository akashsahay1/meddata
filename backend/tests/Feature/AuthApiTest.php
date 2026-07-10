<?php

namespace Tests\Feature;

use App\Models\ApiToken;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\DatabaseSeeder::class);
    }

    private function register(array $overrides = []): \Illuminate\Testing\TestResponse
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

    public function test_forgot_password_returns_ok_with_dev_code_in_debug(): void
    {
        $this->register();

        $res = $this->postJson('/api/v1/auth/forgot-password', [
            'email' => 'user@example.com',
        ])
            ->assertOk()
            ->assertJsonPath('ok', true);

        // APP_DEBUG is true under phpunit env by default (config app.debug).
        $this->assertMatchesRegularExpression('/^\d{6}$/', (string) $res->json('dev_code'));

        $this->assertDatabaseHas('password_reset_codes', [
            'email' => 'user@example.com',
            'code' => $res->json('dev_code'),
        ]);
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
}
