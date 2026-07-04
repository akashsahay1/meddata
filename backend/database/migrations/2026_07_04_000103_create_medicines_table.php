<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('medicines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->nullable()->constrained('stores')->nullOnDelete();
            $table->string('name');
            $table->string('brand')->nullable();
            $table->string('category')->nullable();
            $table->string('batch_no')->nullable();
            $table->string('barcode')->nullable();
            $table->integer('quantity')->default(0);
            $table->string('unit')->nullable();
            $table->date('expiry_date')->nullable();
            $table->decimal('selling_price', 10, 2)->default(0);
            $table->timestamps();
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('medicines');
    }
};
