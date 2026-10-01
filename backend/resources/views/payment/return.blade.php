<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Meddata</title>
<style>
  body { margin: 0; height: 100vh; display: flex; align-items: center; justify-content: center;
         background: #DCE4E2; color: #66807D; font: 600 15px -apple-system, Roboto, sans-serif; }
</style>
</head>
<body>
<div>Finishing payment...</div>
<script>
  try { RZP.postMessage(JSON.stringify(@json($payload))); } catch (e) {}
</script>
</body>
</html>
