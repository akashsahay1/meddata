<?php

namespace Database\Seeders;

use App\Models\Customer;
use App\Models\Medicine;
use App\Models\Plan;
use App\Models\Store;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class DemoDataSeeder extends Seeder
{
    public function run(): void
    {
        $faker = fake('en_IN');

        $cities = [
            'Mumbai' => 'Maharashtra',
            'Pune' => 'Maharashtra',
            'Delhi' => 'Delhi',
            'Bengaluru' => 'Karnataka',
            'Hyderabad' => 'Telangana',
            'Chennai' => 'Tamil Nadu',
            'Kolkata' => 'West Bengal',
            'Ahmedabad' => 'Gujarat',
            'Jaipur' => 'Rajasthan',
            'Lucknow' => 'Uttar Pradesh',
            'Bhubaneswar' => 'Odisha',
            'Patna' => 'Bihar',
        ];
        $cityNames = array_keys($cities);

        $statuses = ['active', 'active', 'active', 'inactive', 'blocked'];

        $planIds = Plan::pluck('id')->all();

        $categories = ['Tablet', 'Syrup', 'Injection', 'Capsule', 'Ointment', 'Drops', 'Inhaler', 'Powder'];
        $units = ['strip', 'bottle', 'vial', 'box', 'tube', 'pack'];
        $brands = ['Cipla', 'Sun Pharma', 'Dr Reddy', 'Mankind', 'Abbott', 'Lupin', 'Zydus', 'Alkem', 'GSK', 'Pfizer'];
        $medNames = [
            'Paracetamol 500', 'Amoxicillin 250', 'Azithromycin 500', 'Cetirizine 10',
            'Pantoprazole 40', 'Metformin 500', 'Amlodipine 5', 'Atorvastatin 10',
            'Ibuprofen 400', 'Omeprazole 20', 'Cough Syrup', 'ORS Powder',
            'Vitamin D3', 'B-Complex', 'Insulin Glargine', 'Salbutamol Inhaler',
            'Diclofenac Gel', 'Betadine Ointment', 'Eye Drops Lubricant', 'Domperidone 10',
        ];

        // ---- ~30 Customers ----
        $customers = [];
        for ($i = 1; $i <= 30; $i++) {
            $city = $cityNames[array_rand($cityNames)];
            $name = $faker->name();
            $customers[] = Customer::create([
                'name' => $name,
                'email' => 'customer' . $i . '.' . Str::lower(Str::random(4)) . '@example.com',
                'phone' => '9' . $faker->numerify('#########'),
                'city' => $city,
                'state' => $cities[$city],
                'status' => $statuses[array_rand($statuses)],
                'plan_id' => $planIds ? $planIds[array_rand($planIds)] : null,
                'device_id' => Str::uuid()->toString(),
                'notes' => $i % 4 === 0 ? $faker->sentence() : null,
            ]);
        }

        // ---- ~40 Stores across customers ----
        $stores = [];
        for ($i = 1; $i <= 40; $i++) {
            /** @var Customer $customer */
            $customer = $customers[array_rand($customers)];
            $city = $cityNames[array_rand($cityNames)];
            $stores[] = Store::create([
                'customer_id' => $customer->id,
                'store_name' => $faker->randomElement(['Sri', 'New', 'City', 'Apollo', 'Care', 'Health', 'Metro', 'Star']) . ' ' .
                    $faker->randomElement(['Medical', 'Pharmacy', 'Medicos', 'Drug House', 'Chemist']),
                'phone' => '8' . $faker->numerify('#########'),
                'address' => $faker->buildingNumber() . ', ' . $faker->streetName(),
                'city' => $city,
                'state' => $cities[$city],
                'pincode' => (string) $faker->numberBetween(110001, 799999),
                'gstin' => $i % 3 === 0 ? strtoupper(Str::random(15)) : null,
                'is_active' => $i % 7 !== 0,
            ]);
        }

        // ---- ~120 Medicines across stores (varied expiry / quantity) ----
        for ($i = 1; $i <= 120; $i++) {
            /** @var Store $store */
            $store = $stores[array_rand($stores)];

            // Mix of expired, expiring-soon, and healthy stock.
            $roll = $i % 5;
            $expiry = match ($roll) {
                0 => now()->subDays(rand(1, 120)),      // expired
                1 => now()->addDays(rand(1, 30)),       // expiring soon
                default => now()->addDays(rand(60, 900)), // healthy
            };

            // Mix of out-of-stock, low, and normal quantity.
            $quantity = match ($i % 6) {
                0 => 0,                 // out of stock
                1 => rand(1, 9),        // low stock
                default => rand(15, 400),
            };

            Medicine::create([
                'store_id' => $store->id,
                'name' => $medNames[array_rand($medNames)],
                'brand' => $brands[array_rand($brands)],
                'category' => $categories[array_rand($categories)],
                'batch_no' => 'B' . strtoupper(Str::random(6)),
                'barcode' => (string) $faker->ean13(),
                'quantity' => $quantity,
                'unit' => $units[array_rand($units)],
                'expiry_date' => $expiry->toDateString(),
                'selling_price' => $faker->randomFloat(2, 10, 1500),
            ]);
        }
    }
}
