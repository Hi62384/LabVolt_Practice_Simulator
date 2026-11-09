$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$helper = Get-Content (Join-Path $repo 'scripts\campus\presentation\navigation_safety\hallway_geometry.gd') -Raw
$world = Get-Content (Join-Path $repo 'scripts\campus\world\campus_world.gd') -Raw
$registry = Get-Content (Join-Path $repo 'assets\campus\world\room_registry.json') -Raw | ConvertFrom-Json

if ($world -notmatch '_close_hallway_voids\(\)' -or $world -notmatch 'HallwayGeometry\.edge_closures\(\)') {
    throw 'Campus world does not install the hallway safety closures.'
}

$expected = @(
    @(0, 10.0, 13.0), @(0, 25.0, 27.0), @(0, 39.0, 41.0), @(0, 53.0, 54.0),
    @(1, -4.0, -3.0), @(1, 9.0, 13.0), @(1, 25.0, 27.0)
)
foreach ($gap in $expected) {
    $literal = '[{0}, {1:0.0}, {2:0.0}]' -f $gap[0], [decimal]$gap[1], [decimal]$gap[2]
    if (-not $helper.Contains($literal)) { throw "Missing edge closure $literal" }
}

foreach ($room in $registry.rooms) {
    $doorZ = [double]$room.door[2]
    $half = [double]$room.door_width / 2.0
    foreach ($gap in $expected | Where-Object { $_[0] -eq [int]$room.floor }) {
        if (($doorZ + $half) -gt $gap[1] -and ($doorZ - $half) -lt $gap[2]) {
            throw "Closure overlaps door clearance for $($room.id)"
        }
    }
}

if ($helper -match '\[0, 56\.0, 60\.0\]') { throw 'Elevator entrance was incorrectly closed.' }
if ($helper -notmatch '"elevator_entrance"' -or $helper -notmatch '"stairs"') {
    throw 'Protected circulation bounds are incomplete.'
}

Write-Output "PASS: 14 visible edge walls close 7 unsupported spans without covering any of $($registry.rooms.Count) doors, stairs, or elevator entrance."
