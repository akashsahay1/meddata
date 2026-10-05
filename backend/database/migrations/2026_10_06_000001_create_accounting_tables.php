<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Accounting (online-only, server-side like billing): parties, purchase
     * entries, payments in/out, sale returns (credit notes) and purchase
     * returns (debit notes). Money is integer paise; ids of documents are
     * device-made UUIDs so a retried request never creates a second one.
     *
     * Party balance sign: positive = the party owes the shop (receivable),
     * negative = the shop owes the party (payable).
     */
    public function up(): void
    {
        Schema::create('parties', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->string('type', 10); // customer|supplier|both
            $table->string('name', 100);
            $table->string('name_norm', 100);
            $table->string('phone', 20)->nullable();
            $table->string('gstin', 15)->nullable();
            $table->string('state_code', 2)->nullable();
            $table->string('address', 500)->nullable();
            // + they owed the shop when added, - the shop owed them.
            $table->bigInteger('opening_balance_paise')->default(0);
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['shop_id', 'name_norm']);
            $table->index(['shop_id', 'phone']);
            $table->index(['shop_id', 'gstin']);
        });

        // Gap-free counters for credit notes (CN) and debit notes (DN), per
        // shop per financial year; bumped under the shop lock like invoices.
        Schema::create('document_series', function (Blueprint $table) {
            $table->id();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->string('kind', 4); // CN|DN
            $table->string('fy', 5);
            $table->unsignedInteger('last_seq')->default(0);
            $table->timestamps();
            $table->unique(['shop_id', 'kind', 'fy']);
        });

        // A supplier's bill: creates/attaches batches and records 'purchase'
        // (+ 'purchase_free') stock movements, which devices pull.
        Schema::create('purchases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->uuid('party_id');
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('device_id', 64)->nullable();
            $table->unsignedBigInteger('invoice_scan_id')->nullable();
            $table->string('supplier_name', 100);
            $table->string('supplier_gstin', 15)->nullable();
            $table->string('supplier_state_code', 2)->nullable();
            $table->string('supplier_invoice_no', 32);
            $table->date('invoice_date');
            $table->date('entry_date');
            $table->boolean('is_inter_state')->default(false);
            $table->unsignedBigInteger('subtotal_paise'); // rate x qty
            $table->unsignedBigInteger('discount_paise');
            $table->unsignedBigInteger('taxable_paise');
            $table->unsignedBigInteger('cgst_paise');
            $table->unsignedBigInteger('sgst_paise');
            $table->unsignedBigInteger('igst_paise');
            $table->bigInteger('round_off_paise');
            $table->unsignedBigInteger('total_paise');
            $table->string('notes', 500)->nullable();
            $table->string('status', 12)->default('final'); // final|cancelled
            $table->timestamp('cancelled_at')->nullable();
            $table->string('cancel_reason')->nullable();
            $table->timestamps();
            $table->index(['shop_id', 'invoice_date']);
            $table->index(['shop_id', 'party_id']);
            $table->index(['shop_id', 'supplier_invoice_no']);
        });

        Schema::create('purchase_items', function (Blueprint $table) {
            $table->id();
            $table->uuid('purchase_id');
            $table->foreign('purchase_id')->references('id')->on('purchases')->cascadeOnDelete();
            $table->unsignedSmallInteger('line_no');
            $table->uuid('product_id');
            $table->uuid('batch_id');
            $table->string('name');
            $table->string('hsn', 16)->nullable();
            $table->string('batch_no', 64)->nullable();
            $table->date('expiry_date');
            $table->date('mfg_date')->nullable();
            // Quantities and rates as printed on the supplier's bill (per pack);
            // stock added = (qty + free_qty) x units_per_pack.
            $table->unsignedInteger('qty');
            $table->unsignedInteger('free_qty')->default(0);
            $table->unsignedInteger('units_per_pack')->default(1);
            $table->unsignedBigInteger('rate_paise'); // per pack, before discount, excl. GST
            $table->unsignedBigInteger('mrp_paise'); // per pack
            $table->unsignedInteger('discount_bp')->default(0);
            $table->unsignedInteger('gst_rate_bp');
            $table->unsignedBigInteger('discount_paise');
            $table->unsignedBigInteger('taxable_paise');
            $table->unsignedBigInteger('cgst_paise');
            $table->unsignedBigInteger('sgst_paise');
            $table->unsignedBigInteger('igst_paise');
            $table->unsignedBigInteger('total_paise');
            $table->boolean('new_batch')->default(true);
            $table->index('purchase_id');
            $table->index('batch_id');
        });

        // Receipts from (in) and payments to (out) a party. Never deleted;
        // a mistake is cancelled.
        Schema::create('party_payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->uuid('party_id');
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('device_id', 64)->nullable();
            $table->string('direction', 3); // in|out
            $table->unsignedBigInteger('amount_paise');
            $table->string('mode', 8); // cash|upi|card|bank|cheque
            $table->string('reference', 64)->nullable();
            $table->date('payment_date');
            $table->string('notes', 500)->nullable();
            $table->uuid('bill_id')->nullable();
            $table->uuid('purchase_id')->nullable();
            $table->string('status', 12)->default('active'); // active|cancelled
            $table->timestamp('cancelled_at')->nullable();
            $table->string('cancel_reason')->nullable();
            $table->timestamps();
            $table->index(['shop_id', 'party_id']);
            $table->index(['shop_id', 'payment_date']);
            $table->index('bill_id');
            $table->index('purchase_id');
        });

        // Credit notes: goods returned against a bill. Tax reversed with the
        // bill's own maths; stock back via 'sale_return' movements.
        Schema::create('sale_returns', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->uuid('bill_id');
            $table->uuid('party_id')->nullable();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('device_id', 64)->nullable();
            $table->string('note_no', 32); // CN/26-27/000001
            $table->string('fy', 5);
            $table->unsignedInteger('seq');
            $table->date('return_date');
            // credit = adjusted against the customer's account; else refunded.
            $table->string('refund_mode', 8);
            $table->string('reason')->nullable();
            $table->string('customer_name', 100)->nullable();
            $table->string('customer_gstin', 15)->nullable();
            $table->string('place_of_supply', 2)->nullable();
            $table->boolean('is_inter_state')->default(false);
            $table->json('seller');
            $table->unsignedBigInteger('subtotal_paise');
            $table->unsignedBigInteger('discount_paise');
            $table->unsignedBigInteger('taxable_paise');
            $table->unsignedBigInteger('cgst_paise');
            $table->unsignedBigInteger('sgst_paise');
            $table->unsignedBigInteger('igst_paise');
            $table->bigInteger('round_off_paise');
            $table->unsignedBigInteger('total_paise');
            $table->timestamps();
            $table->unique(['shop_id', 'fy', 'seq']);
            $table->unique(['shop_id', 'note_no']);
            $table->index(['shop_id', 'return_date']);
            $table->index('bill_id');
        });

        Schema::create('sale_return_items', function (Blueprint $table) {
            $table->id();
            $table->uuid('sale_return_id');
            $table->foreign('sale_return_id')->references('id')->on('sale_returns')->cascadeOnDelete();
            $table->unsignedBigInteger('bill_item_id');
            $table->unsignedSmallInteger('line_no');
            $table->uuid('product_id');
            $table->uuid('batch_id');
            $table->string('name');
            $table->string('hsn', 16)->nullable();
            $table->string('unit', 32)->nullable();
            $table->string('batch_no', 64)->nullable();
            $table->date('expiry_date')->nullable();
            $table->unsignedInteger('qty_units');
            $table->unsignedBigInteger('mrp_paise');
            $table->unsignedInteger('discount_bp')->default(0);
            $table->unsignedBigInteger('discount_paise');
            $table->unsignedInteger('gst_rate_bp');
            $table->unsignedBigInteger('taxable_paise');
            $table->unsignedBigInteger('cgst_paise');
            $table->unsignedBigInteger('sgst_paise');
            $table->unsignedBigInteger('igst_paise');
            $table->unsignedBigInteger('total_paise');
            $table->index('sale_return_id');
            $table->index('bill_item_id');
        });

        // Debit notes: goods sent back to a supplier (stock out via
        // 'purchase_return' movements), optionally against a purchase.
        Schema::create('purchase_returns', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('shop_id')->constrained()->cascadeOnDelete();
            $table->uuid('party_id');
            $table->uuid('purchase_id')->nullable();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('device_id', 64)->nullable();
            $table->string('note_no', 32); // DN/26-27/000001
            $table->string('fy', 5);
            $table->unsignedInteger('seq');
            $table->date('return_date');
            $table->string('reason')->nullable();
            $table->string('supplier_name', 100);
            $table->string('supplier_gstin', 15)->nullable();
            $table->string('supplier_invoice_no', 32)->nullable();
            $table->boolean('is_inter_state')->default(false);
            $table->json('seller');
            $table->unsignedBigInteger('subtotal_paise');
            $table->unsignedBigInteger('discount_paise');
            $table->unsignedBigInteger('taxable_paise');
            $table->unsignedBigInteger('cgst_paise');
            $table->unsignedBigInteger('sgst_paise');
            $table->unsignedBigInteger('igst_paise');
            $table->bigInteger('round_off_paise');
            $table->unsignedBigInteger('total_paise');
            $table->timestamps();
            $table->unique(['shop_id', 'fy', 'seq']);
            $table->unique(['shop_id', 'note_no']);
            $table->index(['shop_id', 'return_date']);
            $table->index('purchase_id');
        });

        Schema::create('purchase_return_items', function (Blueprint $table) {
            $table->id();
            $table->uuid('purchase_return_id');
            $table->foreign('purchase_return_id')->references('id')->on('purchase_returns')->cascadeOnDelete();
            $table->unsignedBigInteger('purchase_item_id')->nullable();
            $table->unsignedSmallInteger('line_no');
            $table->uuid('product_id');
            $table->uuid('batch_id');
            $table->string('name');
            $table->string('hsn', 16)->nullable();
            $table->string('batch_no', 64)->nullable();
            $table->date('expiry_date')->nullable();
            $table->unsignedInteger('qty'); // packs (units when not against a purchase)
            $table->unsignedInteger('units_per_pack')->default(1);
            $table->unsignedBigInteger('rate_paise');
            $table->unsignedInteger('discount_bp')->default(0);
            $table->unsignedInteger('gst_rate_bp');
            $table->unsignedBigInteger('discount_paise');
            $table->unsignedBigInteger('taxable_paise');
            $table->unsignedBigInteger('cgst_paise');
            $table->unsignedBigInteger('sgst_paise');
            $table->unsignedBigInteger('igst_paise');
            $table->unsignedBigInteger('total_paise');
            $table->index('purchase_return_id');
            $table->index('purchase_item_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('purchase_return_items');
        Schema::dropIfExists('purchase_returns');
        Schema::dropIfExists('sale_return_items');
        Schema::dropIfExists('sale_returns');
        Schema::dropIfExists('party_payments');
        Schema::dropIfExists('purchase_items');
        Schema::dropIfExists('purchases');
        Schema::dropIfExists('document_series');
        Schema::dropIfExists('parties');
    }
};
