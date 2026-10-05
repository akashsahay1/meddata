<?php

namespace App\Filament\Resources\Bills;

use App\Filament\Resources\Bills\Pages\ListBills;
use App\Filament\Resources\Bills\Pages\ViewBill;
use App\Filament\Resources\Bills\RelationManagers\ItemsRelationManager;
use App\Filament\Resources\Bills\Schemas\BillInfolist;
use App\Filament\Resources\Bills\Tables\BillsTable;
use App\Models\Bill;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Model;
use UnitEnum;

/** GST bills made in the app. Read-only: bills are created and cancelled from the app only. */
class BillResource extends Resource
{
    protected static ?string $model = Bill::class;

    protected static string|BackedEnum|null $navigationIcon = 'fas-file-invoice';

    protected static string|UnitEnum|null $navigationGroup = 'Shops';

    protected static ?int $navigationSort = 2;

    protected static ?string $recordTitleAttribute = 'invoice_no';

    public static function canCreate(): bool
    {
        return false;
    }

    public static function canEdit(Model $record): bool
    {
        return false;
    }

    public static function canDelete(Model $record): bool
    {
        return false;
    }

    public static function canDeleteAny(): bool
    {
        return false;
    }

    public static function infolist(Schema $schema): Schema
    {
        return BillInfolist::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return BillsTable::configure($table);
    }

    public static function getRelations(): array
    {
        return [
            ItemsRelationManager::class,
        ];
    }

    public static function getPages(): array
    {
        return [
            'index' => ListBills::route('/'),
            'view' => ViewBill::route('/{record}'),
        ];
    }
}
