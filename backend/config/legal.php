<?php

// Who runs Medikabiz, for the website footer and the legal pages
// (resources/views/legal). Razorpay and India's IT and data-protection
// rules expect a postal address and a named grievance officer.
return [
    'company' => 'Yatharthvadi Foundation',
    'address' => env('LEGAL_ADDRESS', 'C/o Alok Singh, Village Ganeshi Kheda, Post Dhanikhera, Unnao, Uttar Pradesh 209801, India'),
    'email' => env('LEGAL_EMAIL', 'support@medikabiz.com'),
    'phone' => '+91 70537 92466',
    'whatsapp' => '917053792466',
    'grievance_officer' => env('LEGAL_GRIEVANCE_OFFICER', 'Alok Singh'),
    'jurisdiction' => env('LEGAL_JURISDICTION', 'Unnao, Uttar Pradesh'),
    'updated' => '17 October 2026',
];
