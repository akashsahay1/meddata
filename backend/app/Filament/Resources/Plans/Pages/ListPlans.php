<?php

namespace App\Filament\Resources\Plans\Pages;

use App\Filament\Resources\Plans\PlanResource;
use App\Services\PlayCatalogService;
use Filament\Actions\Action;
use Filament\Actions\CreateAction;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ListRecords;

class ListPlans extends ListRecords
{
    protected static string $resource = PlanResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Action::make('syncFromPlay')
                ->label('Sync from Google Play')
                ->icon('fab-google-play')
                ->color('gray')
                ->requiresConfirmation()
                ->modalHeading('Sync plans from Google Play')
                ->modalDescription('Pulls the subscription catalog from Google Play and updates billing '
                    . 'fields (price, period). Your names, features and badges are kept.')
                ->action(function (PlayCatalogService $catalog): void {
                    $exit = \Illuminate\Support\Facades\Artisan::call('plans:sync-from-play');
                    Notification::make()
                        ->title($catalog->isLive()
                            ? 'Synced from Google Play'
                            : 'Synced (dev fallback — Play credentials not set)')
                        ->body(trim(\Illuminate\Support\Facades\Artisan::output()))
                        ->success()
                        ->send();
                }),
            CreateAction::make(),
        ];
    }
}
