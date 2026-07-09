<?php

namespace App\Filament\Resources\Coupons\Pages;

use App\Filament\Resources\Coupons\CouponResource;
use App\Models\Coupon;
use Filament\Actions\Action;
use Filament\Actions\CreateAction;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ListRecords;
use Illuminate\Support\Str;

class ListCoupons extends ListRecords
{
    protected static string $resource = CouponResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Action::make('generateCodes')
                ->label('Generate codes')
                ->icon('fas-wand-magic-sparkles')
                ->color('gray')
                ->modalHeading('Bulk-generate coupon codes')
                ->schema([
                    TextInput::make('count')
                        ->label('How many')
                        ->numeric()
                        ->minValue(1)
                        ->maxValue(500)
                        ->default(10)
                        ->required(),
                    Select::make('type')
                        ->options(['percentage' => 'Percentage (%)', 'flat' => 'Flat (₹)'])
                        ->default('percentage')
                        ->required(),
                    TextInput::make('value')
                        ->numeric()
                        ->default(10)
                        ->required(),
                    TextInput::make('prefix')
                        ->label('Prefix (optional)')
                        ->helperText('e.g. SALE → SALEA1B2C3D4')
                        ->maxLength(12),
                ])
                ->action(function (array $data): void {
                    $count = (int) $data['count'];
                    $prefix = strtoupper(trim($data['prefix'] ?? ''));
                    $created = 0;

                    for ($i = 0; $i < $count; $i++) {
                        $code = $prefix . strtoupper(Str::random(8));
                        // Skip the rare collision so we never fail the whole batch.
                        if (Coupon::where('code', $code)->exists()) {
                            continue;
                        }
                        Coupon::create([
                            'code' => $code,
                            'type' => $data['type'],
                            'value' => (float) $data['value'],
                            'is_active' => true,
                        ]);
                        $created++;
                    }

                    Notification::make()
                        ->title("Generated {$created} coupon code(s)")
                        ->success()
                        ->send();
                }),
            CreateAction::make(),
        ];
    }
}
