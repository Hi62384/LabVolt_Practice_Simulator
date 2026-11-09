$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$manifest = Get-Content -Raw (Join-Path $root 'assets\campus\circuit_studio\room.json') | ConvertFrom-Json
if ($manifest.room.id -ne 'circuit_studio') { throw 'Wrong room id' }
if ($manifest.room.door_width -lt 2.4) { throw 'Door clearance regressed' }
$contract = Get-Content -Raw (Join-Path $root 'scripts\campus\facilities\circuit_studio\studio_contract.gd')
foreach ($page in @('studio_ic','studio_pcb','design','code','kits')) { if ($contract -notmatch ('"' + $page + '"')) { throw "Missing route $page" } }
$mount = Get-Content -Raw (Join-Path $root 'scripts\campus\facilities\circuit_studio\mount_controller.gd')
if ($mount -notmatch 'not mount_succeeded') { throw 'Legacy fallback is not guarded' }
Write-Output 'CIRCUIT_STUDIO_STATIC_OK'

