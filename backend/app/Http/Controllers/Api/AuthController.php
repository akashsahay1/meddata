<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ApiToken;
use App\Models\AppSetting;
use App\Models\Entitlement;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;

class AuthController extends Controller
{
    /**
     * POST /auth/register
     * Create an app user, ensure a 7-day trial entitlement, issue a token.
     */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'unique:users,email'],
            'password' => ['required', 'string', 'min:6'],
            'phone' => ['nullable', 'string', 'max:32'],
            'device_id' => ['nullable', 'string'],
        ]);

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'phone' => $data['phone'] ?? null,
            'password' => Hash::make($data['password']),
            'is_admin' => false,
        ]);

        $ent = $this->linkOrCreateEntitlement($user, $data['device_id'] ?? null);
        $token = $user->issueToken('app');

        return response()->json([
            'token' => $token,
            'user' => $this->userPayload($user),
            'entitlement' => $this->entitlementPayload($ent),
        ], 201);
    }

    /**
     * POST /auth/login
     * Verify credentials, optionally link a device entitlement, issue a token.
     */
    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_id' => ['nullable', 'string'],
        ]);

        $user = User::where('email', $data['email'])->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            return response()->json(['message' => 'Invalid credentials'], 422);
        }

        $ent = $this->linkOrCreateEntitlement($user, $data['device_id'] ?? null);
        $token = $user->issueToken('app');

        return response()->json([
            'token' => $token,
            'user' => $this->userPayload($user),
            'entitlement' => $this->entitlementPayload($ent),
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
     * Return the authenticated user + recomputed entitlement.
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        $ent = Entitlement::where('user_id', $user->id)->orderByDesc('id')->first();

        return response()->json([
            'user' => $this->userPayload($user),
            'entitlement' => $this->entitlementPayload($ent),
        ]);
    }

    /**
     * POST /auth/forgot-password
     * Always returns a generic message. When a user exists, store a 6-digit
     * code (15 min TTL) and "email" it (log mailer in local). In debug mode
     * the code is echoed back as dev_code for testing without a mail server.
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
            'expires_at' => now()->addMinutes(15),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        Mail::raw(
            "Your Meddata password reset code is: {$code}\nIt expires in 15 minutes.",
            function ($message) use ($data) {
                $message->to($data['email'])->subject('Meddata password reset code');
            }
        );

        if (config('app.debug')) {
            $generic['dev_code'] = $code;
        }

        return response()->json($generic);
    }

    /**
     * POST /auth/reset-password
     * Verify a non-expired code, set the new password, revoke tokens.
     */
    public function resetPassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'code' => ['required', 'string'],
            'password' => ['required', 'string', 'min:6'],
        ]);

        $row = DB::table('password_reset_codes')
            ->where('email', $data['email'])
            ->where('code', $data['code'])
            ->where('expires_at', '>', now())
            ->first();

        $user = User::where('email', $data['email'])->first();

        if (! $row || ! $user) {
            return response()->json(['message' => 'Invalid or expired code'], 422);
        }

        $user->update(['password' => Hash::make($data['password'])]);

        DB::table('password_reset_codes')->where('email', $data['email'])->delete();
        $user->tokens()->delete();

        return response()->json(['ok' => true]);
    }

    /* ---------------- helpers ---------------- */

    /**
     * Link the given device's entitlement to the user (or create/find one),
     * and start a 7-day trial when the user has none yet.
     */
    private function linkOrCreateEntitlement(User $user, ?string $deviceId): Entitlement
    {
        $existing = Entitlement::where('user_id', $user->id)->orderByDesc('id')->first();

        if ($deviceId) {
            $ent = Entitlement::firstOrNew(['device_id' => $deviceId]);
            $ent->user_id = $user->id;
        } else {
            // No device: reuse the user's entitlement or create one with a
            // synthetic, namespaced device_id (column is NOT NULL).
            $ent = $existing ?: new Entitlement(['device_id' => 'user-' . $user->id]);
            $ent->user_id = $user->id;
        }

        $userHasTrial = $existing && $existing->trial_started_at;

        if (is_null($ent->trial_started_at) && ! $userHasTrial && ! $ent->isActivePaid()) {
            $trialDays = (int) AppSetting::get('trial_days', 7);
            $ent->trial_started_at = now();
            $ent->trial_ends_at = now()->addDays($trialDays);
            if (is_null($ent->source)) {
                $ent->source = 'trial';
            }
        }

        $ent->save();

        return $ent;
    }

    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'phone' => $user->phone,
        ];
    }

    /** Same shape as EntitlementController@show. */
    private function entitlementPayload(?Entitlement $ent): array
    {
        if (! $ent) {
            return [
                'premium' => false,
                'status' => 'expired',
                'source' => null,
                'trial_ends_at' => null,
                'days_left' => 0,
                'expiry_time' => null,
                'product_id' => null,
            ];
        }

        $ent->refreshStatus();
        $ent->save();

        $paidActive = $ent->isActivePaid();
        $trialActive = $ent->isTrialActive();
        $premium = $paidActive || $trialActive;

        $daysLeft = 0;
        if ($paidActive && $ent->expiry_time) {
            $daysLeft = (int) ceil(now()->diffInDays($ent->expiry_time, false));
        } elseif ($trialActive) {
            $daysLeft = (int) ceil(now()->diffInDays($ent->trial_ends_at, false));
        }

        $status = $premium ? 'active' : 'expired';
        $source = $paidActive ? ($ent->source ?: 'razorpay') : ($trialActive ? 'trial' : $ent->source);

        return [
            'premium' => $premium,
            'status' => $status,
            'source' => $source,
            'trial_ends_at' => optional($ent->trial_ends_at)->toIso8601String(),
            'days_left' => max(0, $daysLeft),
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
            'product_id' => $ent->product_id,
        ];
    }
}
