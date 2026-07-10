<?php

namespace App\Http\Middleware;

use App\Models\ApiToken;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AuthenticateApiToken
{
    /**
     * Authenticate the request via a custom Bearer token (no Sanctum).
     * Reads Authorization: Bearer <token>, hashes it (sha-256), finds the
     * matching api_tokens row, and binds the user onto the request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $plain = $request->bearerToken();

        if (! $plain) {
            return $this->unauthenticated();
        }

        $record = ApiToken::where('token', ApiToken::hashToken($plain))->first();

        if (! $record || ! $record->user) {
            return $this->unauthenticated();
        }

        $record->forceFill(['last_used_at' => now()])->saveQuietly();

        $user = $record->user;

        // Bind the user + token onto the request for controllers/auth().
        $request->setUserResolver(fn () => $user);
        $request->attributes->set('api_token', $record);
        auth()->setUser($user);

        return $next($request);
    }

    private function unauthenticated(): Response
    {
        return response()->json(['message' => 'Unauthenticated'], 401);
    }
}
