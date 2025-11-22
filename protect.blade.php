<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{{ $title }}</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
        body { background:#0b1220; color:#e6eef8; font-family:Inter, Arial; display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }
        .card { background:#0f1724; padding:32px; border-radius:12px; box-shadow:0 10px 30px rgba(2,6,23,0.6); max-width:720px; text-align:center; }
        h1 { color:#ff7b72; margin:0 0 12px; font-size:28px; }
        p { color:#9fb0c8; margin:0 0 18px; font-size:16px; }
        .meta { color:#7f98b0; font-size:13px; margin-top:8px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>{{ $title }}</h1>
        <p>{{ $message }}</p>
        <div class="meta">Protected by AntiRusuh</div>
    </div>
</body>
</html>
