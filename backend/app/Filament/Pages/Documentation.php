<?php

namespace App\Filament\Pages;

use BackedEnum;
use Filament\Pages\Page;
use UnitEnum;

class Documentation extends Page
{
    protected static string|BackedEnum|null $navigationIcon = 'fas-book';

    protected static string|UnitEnum|null $navigationGroup = 'System';

    protected static ?int $navigationSort = 99;

    protected static ?string $navigationLabel = 'Documentation';

    protected string $view = 'filament.pages.documentation';

    public function getTitle(): string
    {
        return 'Meddata Backend — Documentation';
    }

    public function getHeading(): string
    {
        return 'Documentation';
    }

    public function getSubheading(): ?string
    {
        return 'How the Meddata backend, admin panel and API work.';
    }
}
