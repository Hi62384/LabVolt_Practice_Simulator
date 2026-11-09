$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$source = Get-Content (Join-Path $repo 'scripts\campus\presentation\navigation_safety\safe_recovery.gd') -Raw
$patch = Get-Content (Join-Path $repo 'review_artifacts\hallway_void_20261106\first_person_safe_recovery.patch') -Raw

foreach ($token in @('const VOID_Y := -8.0', 'observe_grounded', 'needs_recovery', 'recovery_position', 'is_known_walkable')) {
    if (-not $source.Contains($token)) { throw "Missing recovery contract token: $token" }
}
if ($source -match '\b(inventory|reward|ledger|course_progress)\s*[\.=]' -or $source -match '\.rpc(_id)?\s*\(') {
    throw 'Recovery helper mutates unrelated gameplay or network state.'
}
if ($patch -notmatch 'preimage-sha256: BD9BC5A028B154DBF71D99810E1B16D90BC0D42DFDB7C20630097A2AC63156D4') {
    throw 'Reserved player patch is not bound to the inspected preimage.'
}
if ($patch -notmatch 'velocity=Vector3.ZERO' -or $patch -notmatch 'is_on_floor\(\)') {
    throw 'Reserved player patch lacks bounded grounded tracking or velocity reset.'
}
Write-Output 'PASS: local pose-only void recovery is bounded, preimage-bound, and does not touch gameplay state.'

