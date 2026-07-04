<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('purchase_logs', function (Blueprint $table) {
            $table->id();
            $table->string('device_id')->index();
            $table->string('product_id')->nullable();
            $table->string('purchase_token')->nullable();
            $table->string('event')->nullable();   // verify|rtdn:renew|rtdn:cancel|...
            $table->string('result')->nullable();  // active|invalid|error
            $table->json('payload')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('purchase_logs');
    }
};
