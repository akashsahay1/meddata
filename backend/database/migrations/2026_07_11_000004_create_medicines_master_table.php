<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('medicines_master', function (Blueprint $table) {
            // id comes straight from the source CSV, so it is a plain
            // unsigned big integer primary key (not auto-incrementing).
            $table->unsignedBigInteger('id')->primary();
            $table->string('name');
            $table->string('name_norm')->index();
            $table->string('manufacturer')->nullable();
            $table->string('type')->nullable();
            $table->string('pack_size')->nullable();
            $table->text('composition')->nullable();
            $table->decimal('price', 10, 2)->nullable();
            $table->boolean('is_discontinued')->default(false);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('medicines_master');
    }
};
