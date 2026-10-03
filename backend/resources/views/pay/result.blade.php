<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Meddata — {{ $ok ? 'Payment successful' : 'Payment not completed' }}</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
         background: #EEF2F1; color: #0A302E; font: 16px -apple-system, "Segoe UI", Roboto, sans-serif; }
  .card { background: #fff; border-radius: 18px; padding: 32px; max-width: 420px; text-align: center;
          box-shadow: 0 10px 30px rgba(10,48,46,.08); }
  .icon { font-size: 44px; }
  p { color: #66807D; }
</style>
</head>
<body>
<div class="card">
  <div class="icon">{{ $ok ? '✅' : '⚠️' }}</div>
  <h2>{{ $ok ? 'Payment successful' : 'Payment not completed' }}</h2>
  <p>{{ $message }}</p>
  <p>You can close this tab.</p>
</div>
</body>
</html>
