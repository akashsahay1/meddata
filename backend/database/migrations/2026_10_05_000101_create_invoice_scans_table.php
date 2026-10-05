<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * AI purchase-invoice reading. A device uploads a photo/PDF of a supplier
     * bill, a queued job sends it to Claude and stores the extracted lines;
     * the device polls, the user reviews and adds the lines itself (so they
     * sync like any manual add). Files live on the private `local` disk.
     */
    public function up(): void
    {
        Schema::create('invoice_scans', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('file_path');
            $table->string('mime', 64);
            $table->unsignedInteger('file_size')->default(0);
            $table->string('original_name')->nullable();
            // queued | processing | done | failed
            $table->string('status', 16)->default('queued');
            $table->unsignedSmallInteger('attempts')->default(0);
            // Machine-readable failure reason (not_configured, refused, ...).
            $table->string('error_code', 32)->nullable();
            $table->text('error')->nullable();
            // Normalised result: supplier, invoice no/date, items (+ matches).
            $table->json('extracted')->nullable();
            // The model's text when it could not be used, for debugging.
            $table->longText('raw_output')->nullable();
            $table->string('model', 64)->nullable();
            $table->unsignedInteger('input_tokens')->nullable();
            $table->unsignedInteger('output_tokens')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();
            $table->index(['shop_id', 'created_at']);
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('invoice_scans');
    }
};
