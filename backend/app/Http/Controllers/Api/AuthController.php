<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\AdminNewUserMail;
use App\Mail\PasswordResetMail;
use App\Mail\WelcomeMail;
use App\Models\ApiToken;
use App\Models\AppSetting;
use App\Models\User;
use App\Services\CustomerSyncService;
use App\Services\EntitlementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    /** Reset code lifetime and the max number of verification attempts allowed. */
    private const RESET_TTL_MINUTES = 15;

    private const RESET_MAX_ATTEMPTS = 5;

    public function __construct(
        private readonly EntitlementService $entitlements,
        private readonly CustomerSyncService $customers,
    ) {}

    /**
     * POST /auth/register
     * Create an app user, ensure a one-time trial entitlement, issue a token.
     */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', Password::min(8)],
            'phone' => ['nullable', 'string', 'max:32'],
            'device_id' => ['nullable', 'string', 'max:255'],
        ]);

        // is_admin is intentionally NOT taken from input; new API users are never admins.
        $user = new User;
        $user->name = $data['name'];
        $user->email = $data['email'];
        $user->phone = $data['phone'] ?? null;
        $user->password = Hash::make($data['password']);
        $user->is_admin = false;
        $user->save();

        $ent = $this->entitlements->ensureTrial($user, $data['device_id'] ?? null);
        $payload = $this->entitlements->payload($ent);
        $token = $user->issueToken('app');

        // Mirror the new user into the admin "Customers" section.
        $this->customers->syncFromUser($user, $data['device_id'] ?? null);

        $this->sendWelcomeEmails($user, $payload);

        return response()->json([
            'token' => $token,
            'user' => $this->userPayload($user),
            'entitlement' => $payload,
        ], 201);
    }

    /**
     * POST /auth/login
     * Verify credentials, ensure the (one-time) trial, issue a token.
     */
    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_id' => ['nullable', 'string', 'max:255'],
        ]);

        $user = User::where('email', $data['email'])->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            return response()->json(['message' => 'Invalid credentials'], 422);
        }

        $ent = $this->entitlements->ensureTrial($user, $data['device_id'] ?? null);
        $token = $user->issueToken('app');

        // Backfill/refresh the customer mirror for existing users on login too.
        $this->customers->syncFromUser($user, $data['device_id'] ?? null);

        return response()->json([
            'token' => $token,
            'user' => $this->userPayload($user),
            'entitlement' => $this->entitlements->payload($ent),
        ]);
    }

    /**
     * POST /auth/logout (auth.token)
     * Revoke the bearer token used for this request.
     */
    public function logout(Request $request): JsonResponse
    {
        $token = $request->attributes->get('api_token');
        if ($token instanceof ApiToken) {
            $token->delete();
        }

        return response()->json(['ok' => true]);
    }

    /**
     * GET /auth/me (auth.token)
     * Return the authenticated user + current entitlement.
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        $ent = $this->entitlements->forUser($user);

        return response()->json([
            'user' => $this->userPayload($user),
            'entitlement' => $this->entitlements->payload($ent),
        ]);
    }

    /**
     * PATCH /auth/profile (auth.token)
     * Update the authenticated user's name and/or email.
     */
    public function updateProfile(Request $request): JsonResponse
    {
        $user = $request->user();

        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'email' => ['sometimes', 'required', 'email', 'max:255', 'unique:users,email,'.$user->id],
            'phone' => ['sometimes', 'nullable', 'string', 'max:32'],
        ]);

        $user->fill($data);
        $user->save();

        return response()->json(['ok' => true, 'user' => $this->userPayload($user)]);
    }

    /**
     * POST /auth/change-password (auth.token)
     * Change the password for a logged-in user; requires the current password.
     * Revokes all other tokens so other sessions are logged out.
     */
    public function changePassword(Request $request): JsonResponse
    {
        $user = $request->user();

        $data = $request->validate([
            'current_password' => ['required', 'string'],
            'password' => ['required', 'string', Password::min(8), 'different:current_password'],
        ]);

        if (! Hash::check($data['current_password'], $user->password)) {
            return response()->json(['message' => 'Current password is incorrect.'], 422);
        }

        $user->update(['password' => Hash::make($data['password'])]);

        // Keep the current token, drop the rest.
        $current = $request->attributes->get('api_token');
        $user->tokens()->when($current instanceof ApiToken, fn ($q) => $q->where('id', '!=', $current->id))->delete();

        return response()->json(['ok' => true]);
    }

    /**
     * POST /auth/forgot-password
     * Always returns a generic message. When a user exists, store a 6-digit
     * code (15 min TTL, attempt-capped) and email it. The code is only ever
     * echoed back (dev_code) in the local environment for testing.
     */
    public function forgotPassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
        ]);

        $generic = [
            'ok' => true,
            'message' => 'If the email exists, a reset code was sent.',
        ];

        $user = User::where('email', $data['email'])->first();
        if (! $user) {
            return response()->json($generic);
        }

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        DB::table('password_reset_codes')->where('email', $data['email'])->delete();
        DB::table('password_reset_codes')->insert([
            'email' => $data['email'],
            'code' => $code,
            'attempts' => 0,
            'expires_at' => now()->addMinutes(self::RESET_TTL_MINUTES),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->safeMail(fn () => Mail::to($data['email'])->send(new PasswordResetMail($code, self::RESET_TTL_MINUTES)));

        // Only expose the code in local dev and automated tests, never in staging/production.
        if (app()->environment(['local', 'testing'])) {
            $generic['dev_code'] = $code;
        }

        return response()->json($generic);
    }

    /**
     * POST /auth/reset-password
     * Verify a non-expired, attempt-capped code, set the new password, revoke tokens.
     */
    public function resetPassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'code' => ['required', 'string'],
            'password' => ['required', 'string', Password::min(8)],
        ]);

        $row = DB::table('password_reset_codes')
            ->where('email', $data['email'])
            ->where('expires_at', '>', now())
            ->first();

        // No active code, or too many wrong guesses already: fail closed.
        if (! $row || $row->attempts >= self::RESET_MAX_ATTEMPTS) {
            return response()->json(['message' => 'Invalid or expired code'], 422);
        }

        if (! hash_equals((string) $row->code, (string) $data['code'])) {
            DB::table('password_reset_codes')->where('id', $row->id)->increment('attempts');

            // Burn the code once the attempt ceiling is reached.
            if ($row->attempts + 1 >= self::RESET_MAX_ATTEMPTS) {
                DB::table('password_reset_codes')->where('id', $row->id)->delete();
            }

            return response()->json(['message' => 'Invalid or expired code'], 422);
        }

        $user = User::where('email', $data['email'])->first();
        if (! $user) {
            return response()->json(['message' => 'Invalid or expired code'], 422);
        }

        $user->update(['password' => Hash::make($data['password'])]);

        DB::table('password_reset_codes')->where('email', $data['email'])->delete();
        $user->tokens()->delete();

        return response()->json(['ok' => true]);
    }

    /* ---------------- helpers ---------------- */

    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'phone' => $user->phone,
        ];
    }

    /** Send the customer welcome email and notify the admin (best-effort). */
    private function sendWelcomeEmails(User $user, array $entitlement): void
    {
        $this->safeMail(fn () => Mail::to($user->email)->send(new WelcomeMail($user, $entitlement)));

        $admin = AppSetting::get('support_email');
        if ($admin) {
            $this->safeMail(fn () => Mail::to($admin)->send(new AdminNewUserMail($user)));
        }
    }

    /** Run a mail closure without letting a mail failure break the request. */
    private function safeMail(callable $fn): void
    {
        try {
            $fn();
        } catch (\Throwable $e) {
            Log::warning('Mail send failed: '.$e->getMessage());
        }
    }
}
