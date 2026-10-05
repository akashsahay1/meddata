<?php

namespace App\Filament\Resources\Parties;

use App\Filament\Resources\Parties\Pages\ListParties;
use App\Filament\Resources\Parties\Pages\ViewParty;
use App\Filament\Resources\Parties\Schemas\PartyInfolist;
use App\Filament\Resources\Parties\Tables\PartiesTable;
use App\Models\Party;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletingScope;
use UnitEnum;

/** Shops' customers and suppliers. Read-only: parties are managed in the app. */
class PartyResource extends Resource
{
    protected static ?string $model = Party::class;

    protected static string|BackedEnum|null $navigationIcon = 'fas-address-book';

    protected static string|UnitEnum|null $navigationGroup = 'Shops';

    protected static ?int $navigationSort = 3;

    protected static ?string $recordTitleAttribute = 'name';

    protected static ?string $pluralModelLabel = 'parties';

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

    /** Deleted parties are shown too (their documents still name them). */
    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->withoutGlobalScopes([SoftDeletingScope::class]);
    }

    public static function infolist(Schema $schema): Schema
    {
        return PartyInfolist::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return PartiesTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListParties::route('/'),
            'view' => ViewParty::route('/{record}'),
        ];
    }
}
