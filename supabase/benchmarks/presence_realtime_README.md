# Presence Realtime benchmark

This local-only benchmark compares the retired global `online` Presence room
with the current addressed `presence_changed` broadcast. It creates 100
authenticated WebSocket clients, while the target account has 20 friends.
Thus, only 20 of the clients are entitled to receive the current event.

Run it against local Supabase after starting the stack:

```powershell
Get-Content 'supabase/benchmarks/presence_realtime_fixture.sql' |
  docker exec -i supabase_db_Yap_chat psql -v ON_ERROR_STOP=1 -U postgres -d postgres

$benchmarkStatus = npx supabase status -o json | ConvertFrom-Json
$env:SUPABASE_URL = $benchmarkStatus.API_URL
$env:SUPABASE_ANON_KEY = $benchmarkStatus.ANON_KEY
$env:SUPABASE_JWT_SECRET = $benchmarkStatus.JWT_SECRET
node supabase/benchmarks/presence_realtime_benchmark.mjs
```

Always clean the temporary accounts and old-protocol policies afterwards:

```powershell
Get-Content 'supabase/benchmarks/presence_realtime_cleanup.sql' |
  docker exec -i supabase_db_Yap_chat psql -v ON_ERROR_STOP=1 -U postgres -d postgres
```

The benchmark measures delivery fan-out and WebSocket payload bytes, not cloud
latency. Each test client deliberately owns one physical socket, representing a
separate mobile client. In the app, Presence uses the existing shared user
Realtime socket; the optimization reduces recipients and client-side event
work, rather than the number of physical sockets per device.
