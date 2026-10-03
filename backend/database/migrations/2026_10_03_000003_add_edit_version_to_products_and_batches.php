<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * `version` moves on every change (incl. a stock movement recomputing a
     * batch's qty) so devices pull it. `edit_version` moves only on real
     * edits (price, expiry, name...), and is what conflict checks compare,
     * so a sale on one device doesn't make a price edit on another conflict.
     */
    public function up(): void
    {
        foreach (['products', 'batches'] as $table) {
            Schema::table($table, function (Blueprint $t) {
                $t->unsignedBigInteger('edit_version')->default(0)->after('version');
            });
        }
    }

    public function down(): void
    {
        foreach (['products', 'batches'] as $table) {
            Schema::table($table, function (Blueprint $t) {
                $t->dropColumn('edit_version');
            });
        }
    }
};
