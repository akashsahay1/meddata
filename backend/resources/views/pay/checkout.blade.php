<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Meddata — Secure checkout</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
         background: #EEF2F1; color: #0A302E; font: 16px -apple-system, "Segoe UI", Roboto, sans-serif; }
  .card { background: #fff; border-radius: 18px; padding: 32px; max-width: 420px; text-align: center;
          box-shadow: 0 10px 30px rgba(10,48,46,.08); }
  button { background: #FF6B2C; color: #fff; border: 0; border-radius: 14px; padding: 14px 28px;
           font-size: 16px; font-weight: 700; cursor: pointer; margin-top: 16px; }
  p { color: #66807D; }
</style>
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
</head>
<body>
<div class="card">
  <h2>Meddata Pro</h2>
  <p>Opening secure Razorpay checkout…</p>
  <button id="pay" type="button">Pay now</button>
</div>
<script>
  // The result is posted to the server (callback_url), which verifies it
  // and activates the subscription; nothing depends on this tab afterwards.
  var options = @json($options);
  function open() { new Razorpay(options).open(); }
  document.getElementById('pay').onclick = open;
  window.onload = open;
</script>
</body>
</html>
