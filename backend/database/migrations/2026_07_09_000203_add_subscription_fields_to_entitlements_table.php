<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('entitlements', function (Blueprint $table) {
            $table->dateTime('trial_started_at')->nullable()->after('is_premium');
            $table->dateTime('trial_ends_at')->nullable()->after('trial_started_at');
            $table->string('source')->nullable()->after('trial_ends_at'); // trial|razorpay|manual|coupon
            $table->string('razorpay_payment_id')->nullable()->after('source');
            $table->string('razorpay_order_id')->nullable()->after('razorpay_payment_id');
            $table->foreignId('coupon_id')->nullable()->after('razorpay_order_id')->constrained()->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('entitlements', function (Blueprint $table) {
            $table->dropConstrainedForeignId('coupon_id');
            $table->dropColumn([
                'trial_started_at', 'trial_ends_at', 'source',
                'razorpay_payment_id', 'razorpay_order_id',
            ]);
        });
    }
};
