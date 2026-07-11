<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Track verification attempts per reset code so a code can be invalidated after
 * a small number of wrong guesses - closing the 6-digit brute-force window.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('password_reset_codes', function (Blueprint $table) {
            $table->unsignedTinyInteger('attempts')->default(0)->after('code');
        });
    }

    public function down(): void
    {
        Schema::table('password_reset_codes', function (Blueprint $table) {
            $table->dropColumn('attempts');
        });
    }
};
