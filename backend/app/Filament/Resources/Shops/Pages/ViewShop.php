<?php

namespace App\Filament\Resources\Shops\Pages;

use App\Filament\Resources\Shops\ShopResource;
use App\Models\Shop;
use App\Rules\Gstin;
use App\Support\GstStates;
use App\Support\ShopDetails;
use Filament\Actions\Action;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ViewRecord;
use Illuminate\Validation\ValidationException;

class ViewShop extends ViewRecord
{
    protected static string $resource = ShopResource::class;

    /** Fields printed on the shop's invoices (same rules as PATCH /shops/current). */
    private const INVOICE_FIELDS = [
        'name', 'legal_name', 'gstin', 'state_code', 'address', 'phone',
        'drug_license_no', 'invoice_prefix', 'default_gst_rate_bp',
    ];

    protected function getHeaderActions(): array
    {
        $upper = fn (?string $state, callable $set, string $field) => $set($field, $state === null ? null : strtoupper(trim($state)));

        return [
            Action::make('editInvoiceDetails')
                ->label('Edit invoice details')
                ->icon('fas-pen')
                ->modalHeading('Invoice details')
                ->modalDescription('Printed on the shop\'s GST invoices. Bills already made keep the details they were printed with.')
                ->fillForm(fn (Shop $record): array => $record->only(self::INVOICE_FIELDS))
                ->schema([
                    TextInput::make('name')
                        ->label('Shop name')
                        ->required()
                        ->maxLength(255),
                    TextInput::make('legal_name')
                        ->label('Legal name')
                        ->helperText('Registered business name, if different.')
                        ->maxLength(255),
                    TextInput::make('gstin')
                        ->label('GSTIN')
                        ->live(onBlur: true)
                        ->afterStateUpdated(fn (?string $state, callable $set) => $upper($state, $set, 'gstin'))
                        ->rules([new Gstin]),
                    Select::make('state_code')
                        ->label('State')
                        ->options(GstStates::options())
                        ->searchable(),
                    Textarea::make('address')
                        ->maxLength(1000)
                        ->rows(2),
                    TextInput::make('phone')
                        ->maxLength(32),
                    TextInput::make('drug_license_no')
                        ->label('Drug licence no.')
                        ->maxLength(255),
                    TextInput::make('invoice_prefix')
                        ->label('Invoice prefix')
                        ->helperText('Up to 3 letters/digits, e.g. MED -> MED/26-27/000001. Blank = INV.')
                        ->live(onBlur: true)
                        ->afterStateUpdated(fn (?string $state, callable $set) => $upper($state, $set, 'invoice_prefix'))
                        ->rules(['nullable', 'regex:/^[A-Za-z0-9]{1,3}$/']),
                    Select::make('default_gst_rate_bp')
                        ->label('GST rate for products without one')
                        ->options([0 => '0%', 500 => '5%', 1200 => '12%', 1800 => '18%', 2800 => '28%'])
                        ->required(),
                ])
                ->action(function (array $data, Shop $record, Action $action): void {
                    $data = ShopDetails::prepare($data);
                    try {
                        $changes = ShopDetails::merge($record->only(self::INVOICE_FIELDS), $data);
                    } catch (ValidationException $e) {
                        Notification::make()->danger()->title(collect($e->errors())->flatten()->first())->send();
                        $action->halt();

                        return;
                    }
                    $record->fill($changes)->save();
                    Notification::make()->success()->title('Invoice details saved')->send();
                }),
        ];
    }
}
