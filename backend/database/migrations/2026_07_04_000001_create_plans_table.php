<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('plans', function (Blueprint $table) {
            $table->id();
            $table->string('name');                 // e.g. "Yearly Plan"
            $table->string('product_id')->unique(); // Play product id
            $table->string('billing_period');       // monthly | yearly | lifetime | free
            $table->decimal('price', 10, 2)->default(0);
            $table->string('currency', 8)->default('INR');
            $table->string('badge')->nullable();     // e.g. "BEST VALUE"
            $table->boolean('is_best_value')->default(false);
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->json('features')->nullable();    // list of feature strings
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('plans');
    }
};
