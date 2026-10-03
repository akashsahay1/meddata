<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Server-synced inventory. Ids are UUIDs generated on devices, money is
     * integer paise and quantities are integer units. Every row carries the
     * shop-wide `version` it was last changed at, plus a tombstone.
     */
    public function up(): void
    {
        Schema::create('products', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $this->syncColumns($table);
            $this->editVersion($table);
            $table->string('name');
            $table->string('name_norm');
            $table->string('manufacturer')->nullable();
            $table->string('category')->nullable();
            $table->text('composition')->nullable();
            $table->string('unit', 32)->default('Tablets');
            $table->unsignedInteger('pack_size')->default(1);
            $table->string('hsn', 16)->nullable();
            $table->unsignedInteger('gst_rate_bp')->nullable();
            $table->string('barcode', 64)->nullable();
            $table->unsignedInteger('low_stock_threshold_units')->default(10);
            // Selling price = batch MRP minus this discount (basis points).
            $table->unsignedInteger('discount_bp')->default(0);
            $table->unsignedBigInteger('master_id')->nullable();
            $table->text('notes')->nullable();
            $table->index(['shop_id', 'name_norm']);
            $table->index(['shop_id', 'barcode']);
        });

        Schema::create('batches', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $this->syncColumns($table);
            $this->editVersion($table);
            $table->uuid('product_id');
            $table->string('batch_no', 64)->nullable();
            $table->date('expiry_date');
            $table->date('mfg_date')->nullable();
            $table->unsignedBigInteger('mrp_paise')->default(0);
            $table->unsignedBigInteger('purchase_rate_paise')->default(0);
            // Cache of SUM(stock_movements.delta_units). Recomputed on the
            // server, never accepted from clients. May go negative (flagged).
            $table->bigInteger('qty_units')->default(0);
            $table->index(['shop_id', 'product_id']);
            $table->index(['shop_id', 'expiry_date']);
        });

        // Append-only stock ledger.
        Schema::create('stock_movements', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $this->syncColumns($table);
            $table->uuid('batch_id');
            $table->uuid('product_id');
            $table->bigInteger('delta_units');
            $table->string('reason', 24);
            $table->string('ref_type', 32)->nullable();
            $table->uuid('ref_id')->nullable();
            $table->timestamp('occurred_at');
            $table->index(['shop_id', 'batch_id']);
        });

        // Append-only audit of price edits; written by the server and pulled
        // read-only by devices.
        Schema::create('price_changes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $this->syncColumns($table);
            $table->uuid('batch_id');
            $table->string('field', 32);
            $table->unsignedBigInteger('old_paise')->nullable();
            $table->unsignedBigInteger('new_paise')->nullable();
            $table->index(['shop_id', 'batch_id']);
        });
    }

    /**
     * `version` moves on every change (incl. a stock movement recomputing a
     * batch's qty) so devices pull it; `edit_version` moves only on real
     * edits and is what conflict checks compare, so a sale on one device
     * doesn't make a price edit on another conflict.
     */
    private function editVersion(Blueprint $table): void
    {
        $table->unsignedBigInteger('edit_version')->default(0);
    }

    private function syncColumns(Blueprint $table): void
    {
        $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
        $table->unsignedBigInteger('version');
        $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
        $table->string('device_id', 64)->nullable();
        $table->timestamps();
        $table->softDeletes();
        $table->index(['shop_id', 'version']);
    }

    public function down(): void
    {
        Schema::dropIfExists('price_changes');
        Schema::dropIfExists('stock_movements');
        Schema::dropIfExists('batches');
        Schema::dropIfExists('products');
    }
};
