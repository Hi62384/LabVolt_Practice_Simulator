$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$router = Get-Content -Raw (Join-Path $root 'scripts\campus\dorms\interactions\personal_station_router.gd')
$fallback = Get-Content -Raw (Join-Path $root 'scripts\campus\dorms\interactions\shop_fallback_policy.gd')
$shop = Get-Content -Raw (Join-Path $root 'scripts\shop_room.gd')
$required = @(
    'room_for_peer',
    'authenticated_identity',
    'owner_identity',
    'game.electronics.open(page)',
    '"kit_workshop": "kits"',
    '"loadout": "inventory"',
    '"notes": "notes"',
    '_close_owned_ui()',
    'replacements_ready_for_local_owner()'
)
foreach ($token in $required) {
    if (-not $router.Contains($token)) { throw "Missing router contract token: $token" }
}
if (-not $fallback.Contains('if page not in PERSONAL_PAGES:return true')) { throw 'Unrelated shop pages are not explicitly preserved' }
foreach ($page in @('"shop"','"ics"','"trade"')) {
    if (-not $shop.Contains($page)) { throw "Existing unrelated shop route disappeared: $page" }
}
if ($router -match 'profile\.data|ConfigFile|user://|session\.request|\.rpc') { throw 'Dorm router must not read/write profile data or create an authority path' }
Write-Output 'PASS: dorm interactions use authenticated room ownership, existing UI routes, cleanup, and safe shop fallback.'
