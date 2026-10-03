<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Shared medicine catalog searched by every shop. Seeded from the Indian
     * medicine CSV (`seed_id` = the CSV id, upserted by medicines:import) and
     * grown by shops: a product a shop adds that isn't here yet is added with
     * source = 'shop' so other shops find it too.
     */
    public function up(): void
    {
        Schema::create('medicines_master', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('seed_id')->nullable()->unique();
            $table->string('name');
            $table->string('name_norm')->index();
            $table->string('manufacturer')->nullable();
            $table->string('manufacturer_norm')->nullable()->index();
            $table->string('type')->nullable();
            $table->string('pack_size')->nullable();
            $table->text('composition')->nullable();
            $table->decimal('price', 10, 2)->nullable();
            $table->boolean('is_discontinued')->default(false);
            $table->string('barcode', 64)->nullable()->index();
            $table->string('hsn', 16)->nullable();
            $table->unsignedInteger('gst_rate_bp')->nullable();
            $table->string('source', 8)->default('seed')->index(); // seed|shop|admin
            // No FK: this table is created before `shops`.
            $table->unsignedBigInteger('created_by_shop_id')->nullable()->index();
            $table->unsignedBigInteger('created_by_user_id')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('medicines_master');
    }
};
