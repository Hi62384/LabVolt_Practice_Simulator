$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$contractPath = Join-Path $root 'assets\campus\dorms\dorm_layout_contract.json'
$sessionPath = Join-Path $root 'scripts\session.gd'
$layoutPath = Join-Path $root 'scripts\campus\dorms\world\dorm_layout.gd'
$hallPath = Join-Path $root 'scripts\campus\dorms\world\dorm_hall.gd'
$campusWorldPath = Join-Path $root 'scripts\campus\world\campus_world.gd'
$hookPath = Join-Path $root 'tools\campus\dorms\SHARED_ASSEMBLY_HOOK.md'
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$session = Get-Content -LiteralPath $sessionPath -Raw
$layout = Get-Content -LiteralPath $layoutPath -Raw
$hall = Get-Content -LiteralPath $hallPath -Raw
$campusWorld = Get-Content -LiteralPath $campusWorldPath -Raw
$hook = Get-Content -LiteralPath $hookPath -Raw

function Require([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$match = [regex]::Match($session, 'create_server\(port\s*,\s*(\d+)\)')
Require $match.Success 'Could not find the authoritative ENet max-client expression.'
$maxClients = [int]$match.Groups[1].Value
$capacity = $maxClients + 1
Require ($capacity -eq [int]$contract.capacity_binding.player_capacity) 'Dorm contract capacity no longer matches authoritative session capacity.'
Require ($contract.layout.rooms_per_side * 2 -ge $capacity) 'Layout does not provide one room per possible player.'
Require ([double]$contract.connection.hall_entry[2] -eq [double]$contract.connection.campus_corridor_edge_z) 'Hall entry is disconnected from the campus corridor edge.'
Require ($campusWorld.Contains('box(self,Vector3(13,y+2,68),Vector3(6,4,.16),"a6b9b4")') -or $campusWorld.Contains('Four-metre clear portal into the capacity-driven dorm hall.')) 'Campus north-edge preimage changed; re-review the shared portal hook.'
Require ($hook.Contains('7dada66f0d8f30eb0de950a6366476b45cd039fed8850198dd693717c9aba37e')) 'Shared portal hook lacks its campus-world preimage hash.'
Require ($layout.Contains('func room_contract(index: int, capacity: int)')) 'Capacity-driven room contract is missing.'
Require ($layout.Contains('for index in range(maxi(capacity, 1))')) 'Room enumeration is not capacity-driven.'

foreach ($required in @('DoorPivot','CollisionShape3D','EntryAnchor','RoomAnchor','WorkshopAnchor','LoadoutNotesAnchor')) {
    Require ($hall.Contains($required)) "Missing stable node/anchor $required."
}
foreach ($required in @('OpenKitBase','Breadboard','Component','BackpackBody','Paper','BedFrame','Wardrobe')) {
    Require ($hall.Contains($required)) "Missing visible furnishing $required."
}
Require (-not $hall.Contains('OmniLight3D')) 'Per-room real-time OmniLight3D is forbidden.'
Require (-not $hall.Contains('Label3D.new')) 'Workstations must be physical props, not text boxes.'
Require ($hall.Contains('door_targets[contract.dorm_id]')) 'Door targets are not published by stable dorm_id.'

$roomDepth = [double]$contract.layout.room_size[2]
$stride = [double]$contract.layout.room_stride
Require ($stride -ge $roomDepth) 'Adjacent room shells overlap.'
Require ($stride -eq $roomDepth) 'Room entry-wall spans leave a gap or overlap along the hall.'
$doorWidth = [double]$contract.layout.door_width
Require ($doorWidth -ge 1.1) 'Door clearance is below the authored body-clear width.'
Require ($doorWidth -lt $roomDepth) 'Door opening cannot fit in room entry wall.'

Write-Output "Dorm world contract valid: $capacity rooms, connected at z=$($contract.connection.campus_corridor_edge_z), stable anchors and physical workstations present."
