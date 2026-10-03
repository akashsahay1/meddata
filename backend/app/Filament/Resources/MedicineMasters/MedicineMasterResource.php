<?php

namespace App\Filament\Resources\MedicineMasters;

use App\Filament\Resources\MedicineMasters\Pages\ListMedicineMasters;
use App\Filament\Resources\MedicineMasters\Tables\MedicineMastersTable;
use App\Models\MedicineMaster;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Model;
use UnitEnum;

/** Shared medicine catalog (CSV seed + shop-added). Read-only, list only. */
class MedicineMasterResource extends Resource
{
    protected static ?string $model = MedicineMaster::class;

    protected static string|BackedEnum|null $navigationIcon = 'fas-book-medical';

    protected static string|UnitEnum|null $navigationGroup = 'Catalog';

    protected static ?string $navigationLabel = 'Master catalog';

    protected static ?string $modelLabel = 'master medicine';

    protected static ?string $slug = 'medicine-master';

    protected static ?int $navigationSort = 1;

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

    public static function table(Table $table): Table
    {
        return MedicineMastersTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListMedicineMasters::route('/'),
        ];
    }
}
