<?php

namespace App\Filament\Resources\PurchaseLogs;

use App\Filament\Resources\PurchaseLogs\Pages\CreatePurchaseLog;
use App\Filament\Resources\PurchaseLogs\Pages\EditPurchaseLog;
use App\Filament\Resources\PurchaseLogs\Pages\ListPurchaseLogs;
use App\Filament\Resources\PurchaseLogs\Schemas\PurchaseLogForm;
use App\Filament\Resources\PurchaseLogs\Tables\PurchaseLogsTable;
use App\Models\PurchaseLog;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use UnitEnum;

class PurchaseLogResource extends Resource
{
    protected static ?string $model = PurchaseLog::class;

    protected static string|BackedEnum|null $navigationIcon = 'fas-receipt';

    protected static string|UnitEnum|null $navigationGroup = 'Subscriptions';

    protected static ?int $navigationSort = 3;

    public static function form(Schema $schema): Schema
    {
        return PurchaseLogForm::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return PurchaseLogsTable::configure($table);
    }

    public static function getRelations(): array
    {
        return [
            //
        ];
    }

    public static function getPages(): array
    {
        return [
            'index' => ListPurchaseLogs::route('/'),
            'create' => CreatePurchaseLog::route('/create'),
            'edit' => EditPurchaseLog::route('/{record}/edit'),
        ];
    }
}
