<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /** Backfill the admin-editable support WhatsApp number on existing installs. */
    public function up(): void
    {
        DB::table('app_settings')->insertOrIgnore([
            'key' => 'support_whatsapp',
            'value' => '',
            'type' => 'string',
            'label' => 'Support WhatsApp number (with country code)',
            'group' => 'general',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        DB::table('app_settings')->where('key', 'support_whatsapp')->delete();
    }
};
