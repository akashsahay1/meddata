<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Str;

#[Fillable(['name', 'email', 'phone', 'password', 'is_admin'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable implements FilamentUser
{
    /** @use HasFactory<UserFactory> */
    use HasFactory, Notifiable;

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_admin' => 'boolean',
        ];
    }

    /** Only admins may enter the Filament panel. */
    public function canAccessPanel(Panel $panel): bool
    {
        return $this->is_admin === true;
    }

    /** All bearer tokens issued to this user. */
    public function tokens(): HasMany
    {
        return $this->hasMany(ApiToken::class);
    }

    /** The user's current entitlement (latest by id). */
    public function entitlement(): HasOne
    {
        return $this->hasOne(Entitlement::class)->latestOfMany();
    }

    /**
     * Issue a new bearer token for this user.
     * Stores only the SHA-256 hash; returns the PLAINTEXT token once.
     */
    public function issueToken(string $name = 'app'): string
    {
        $plain = Str::random(64);

        $this->tokens()->create([
            'token' => ApiToken::hashToken($plain),
            'name' => $name,
        ]);

        return $plain;
    }
}
