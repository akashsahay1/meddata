<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Tenancy: every app user belongs to a shop and shop data is scoped by
     * shop_id. One owner login per shop for now; shop_users keeps staff
     * roles possible later without another migration.
     */
    public function up(): void
    {
        Schema::create('shops', function (Blueprint $table) {
            $table->id();
            $table->foreignId('owner_user_id')->constrained('users')->cascadeOnDelete();
            // Trade name (shown in the app); legal_name is the registered
            // business name printed on tax invoices when it differs.
            $table->string('name');
            $table->string('legal_name')->nullable();
            $table->string('gstin', 15)->nullable();
            $table->string('state_code', 2)->nullable();
            $table->string('drug_license_no')->nullable();
            $table->text('address')->nullable();
            $table->string('phone', 32)->nullable();
            // Up to 3 characters so PREFIX/26-27/000042 stays within the
            // 16-character limit GST rules set for invoice numbers.
            $table->string('invoice_prefix', 12)->nullable();
            // GST rate used on a bill for products that have none set
            // (basis points; 500 = 5%, the usual rate for medicines).
            $table->unsignedInteger('default_gst_rate_bp')->default(500);
            // Monotonic per-shop change counter. Every synced row change takes
            // the next value as its `version`, giving devices a single cursor.
            $table->unsignedBigInteger('seq')->default(0);
            $table->timestamps();
        });

        Schema::create('shop_users', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('role', 16)->default('owner');
            $table->timestamps();
            $table->unique(['shop_id', 'user_id']);
        });

        Schema::create('shop_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('device_uuid', 64);
            $table->string('name')->nullable();
            $table->string('platform', 16)->nullable();
            $table->string('app_version', 32)->nullable();
            $table->unsignedBigInteger('last_pull_version')->default(0);
            $table->timestamp('last_sync_at')->nullable();
            $table->timestamps();
            $table->unique(['shop_id', 'device_uuid']);
        });

        // Idempotency log for pushed mutations: re-sending the same mutation
        // id returns the stored result instead of applying it twice.
        Schema::create('sync_mutations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->uuid('mutation_id');
            $table->json('result');
            $table->timestamp('created_at')->nullable();
            $table->unique(['shop_id', 'mutation_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sync_mutations');
        Schema::dropIfExists('shop_devices');
        Schema::dropIfExists('shop_users');
        Schema::dropIfExists('shops');
    }
};
