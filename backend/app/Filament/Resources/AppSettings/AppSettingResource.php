<?php

namespace App\Filament\Resources\AppSettings;

use App\Filament\Resources\AppSettings\Pages\CreateAppSetting;
use App\Filament\Resources\AppSettings\Pages\EditAppSetting;
use App\Filament\Resources\AppSettings\Pages\ListAppSettings;
use App\Filament\Resources\AppSettings\Schemas\AppSettingForm;
use App\Filament\Resources\AppSettings\Tables\AppSettingsTable;
use App\Models\AppSetting;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use UnitEnum;

class AppSettingResource extends Resource
{
    protected static ?string $model = AppSetting::class;

    protected static string|BackedEnum|null $navigationIcon = 'fas-gear';

    protected static string|UnitEnum|null $navigationGroup = 'System';

    protected static ?int $navigationSort = 4;

    public static function form(Schema $schema): Schema
    {
        return AppSettingForm::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return AppSettingsTable::configure($table);
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
            'index' => ListAppSettings::route('/'),
            'create' => CreateAppSetting::route('/create'),
            'edit' => EditAppSetting::route('/{record}/edit'),
        ];
    }
}
