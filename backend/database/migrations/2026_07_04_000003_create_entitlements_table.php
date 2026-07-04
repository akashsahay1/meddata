<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('entitlements', function (Blueprint $table) {
            $table->id();
            $table->string('device_id')->index();
            $table->foreignId('plan_id')->nullable()->constrained()->nullOnDelete();
            $table->string('product_id')->nullable();
            $table->string('status')->default('expired'); // active|grace|expired|canceled
            $table->string('purchase_token')->nullable();
            $table->timestamp('expiry_time')->nullable();
            $table->boolean('is_premium')->default(false);
            $table->timestamps();

            $table->index(['device_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('entitlements');
    }
};
