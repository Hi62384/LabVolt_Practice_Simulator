$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$registry = Get-Content -Raw (Join-Path $root 'assets\campus\world\room_registry.json') | ConvertFrom-Json
$geometry = Get-Content -Raw (Join-Path $PSScriptRoot 'geometry\exterior_finish.gd')
$signage = Get-Content -Raw (Join-Path $PSScriptRoot 'entrance_signage.gd')
if ($registry.entrance[0] -ne 13 -or $registry.entrance[2] -ne -18) { throw 'Spawn moved; recheck mounts' }
if ($geometry -notmatch 'Vector3\(13,4\.54,-11\.32\)') { throw 'Portal anchor changed' }
if ($signage -notmatch 'Vector3\(13, 4\.54, -11\.57\), PI, Vector2\(6\.4, 0\.84\)') { throw 'Sign no longer mounts to portal front' }
if ($signage -notmatch 'double_sided = false' -or $signage -match 'BILLBOARD_') { throw 'Physical one-sided sign contract failed' }
$rooms = @($registry.rooms)
if (@($rooms | Select-Object -ExpandProperty number -Unique).Count -ne $rooms.Count) { throw 'Duplicate room number' }
if (@($rooms | Select-Object -ExpandProperty id -Unique).Count -ne $rooms.Count) { throw 'Duplicate room ID' }
foreach ($room in $rooms) {
    if ($room.door[0] -notin @(10,16)) { throw "Unexpected corridor side: $($room.id)" }
    if ($room.floor -notin @(0,1)) { throw "Unexpected floor: $($room.id)" }
}
if (@($rooms | Where-Object floor -eq 0).Count -ne 8 -or @($rooms | Where-Object floor -eq 1).Count -ne 8) { throw 'Directory room count changed' }
if ($signage -notmatch '"Shop & Trading"' -or $signage -match 'Kit Editor / Trading') { throw 'M102 display mismatch' }
'Entrance mount, registry IDs, floor groups and one-sided text contract passed.'
