<?php

namespace App\Filament\Resources\Entitlements;

use App\Filament\Resources\Entitlements\Pages\CreateEntitlement;
use App\Filament\Resources\Entitlements\Pages\EditEntitlement;
use App\Filament\Resources\Entitlements\Pages\ListEntitlements;
use App\Filament\Resources\Entitlements\Schemas\EntitlementForm;
use App\Filament\Resources\Entitlements\Tables\EntitlementsTable;
use App\Models\Entitlement;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use UnitEnum;

class EntitlementResource extends Resource
{
    protected static ?string $model = Entitlement::class;

    protected static string|BackedEnum|null $navigationIcon = 'fas-crown';

    protected static string|UnitEnum|null $navigationGroup = 'Subscriptions';

    protected static ?int $navigationSort = 2;

    public static function form(Schema $schema): Schema
    {
        return EntitlementForm::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return EntitlementsTable::configure($table);
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
            'index' => ListEntitlements::route('/'),
            'create' => CreateEntitlement::route('/create'),
            'edit' => EditEntitlement::route('/{record}/edit'),
        ];
    }
}
