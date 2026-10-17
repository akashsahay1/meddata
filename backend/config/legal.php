<?php

// Who runs Medikabiz, for the website footer and the legal pages
// (resources/views/legal). Fill the blanks before the site goes live:
// Razorpay and India's IT and data-protection rules expect a postal
// address and a named grievance officer.
return [
    'company' => 'Yatharthvadi Foundation',
    'address' => env('LEGAL_ADDRESS', '[Registered office address]'),
    'email' => env('LEGAL_EMAIL', 'support@medikabiz.com'),
    'phone' => '+91 70537 92466',
    'whatsapp' => '917053792466',
    'grievance_officer' => env('LEGAL_GRIEVANCE_OFFICER', '[Name of the grievance officer]'),
    'jurisdiction' => env('LEGAL_JURISDICTION', '[City]'),
    'updated' => '17 October 2026',
];
