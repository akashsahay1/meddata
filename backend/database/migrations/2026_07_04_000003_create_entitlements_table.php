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
            // One entitlement per user (trial or paid).
            $table->foreignId('user_id')->nullable()->unique()->constrained()->nullOnDelete();
            $table->foreignId('plan_id')->nullable()->constrained()->nullOnDelete();
            $table->string('product_id')->nullable();
            $table->string('status')->default('expired'); // active|grace|expired|canceled
            $table->string('purchase_token')->nullable();
            $table->timestamp('expiry_time')->nullable();
            $table->boolean('is_premium')->default(false);
            $table->dateTime('trial_started_at')->nullable();
            $table->dateTime('trial_ends_at')->nullable();
            $table->string('source')->nullable(); // trial|razorpay|manual|coupon
            $table->string('razorpay_payment_id')->nullable();
            $table->string('razorpay_order_id')->nullable();
            $table->foreignId('coupon_id')->nullable()->constrained()->nullOnDelete();
            $table->timestamps();

            $table->index(['device_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('entitlements');
    }
};
