$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$toon = Join-Path $root 'scripts\toon_character.gd'
$glb = Join-Path $root 'assets\default_avatar.glb'

$source = Get-Content -LiteralPath $toon -Raw
if ($source -notmatch 'ellipsoid\(arm,Vector3\(0,-\.48,\.012\).+"Hand"\)') {
    throw 'Palm mesh creation is missing.'
}
if ($source -notmatch 'ellipsoid\(arm,Vector3\(-side\*\.05,-\.455,\.028\).+"Thumb"\)') {
    throw 'Thumb mesh creation is missing.'
}

$bytes = [IO.File]::ReadAllBytes($glb)
if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'glTF') {
    throw 'Default avatar is not a binary glTF.'
}
$jsonLength = [BitConverter]::ToUInt32($bytes, 12)
$json = [Text.Encoding]::UTF8.GetString($bytes, 20, $jsonLength).TrimEnd([char]0, [char]32) | ConvertFrom-Json
$armIndex = -1
for ($i = 0; $i -lt $json.nodes.Count; $i++) {
    if ($json.nodes[$i].name -eq 'ArmR') { $armIndex = $i; break }
}
if ($armIndex -lt 0) { throw 'ArmR is missing from the default avatar.' }
$children = @($json.nodes[$armIndex].children | ForEach-Object { $json.nodes[$_] })
if (-not ($children.name -contains 'Hand2')) { throw 'Right palm is missing.' }
if (-not ($children.name -contains 'Thumb2')) { throw 'Right thumb is missing.' }
$anonymous = @($children | Where-Object { $_.name -like '_MeshInstance3D_*' })

Write-Output ('toon_sha256=' + (Get-FileHash -Algorithm SHA256 $toon).Hash)
Write-Output ('glb_sha256=' + (Get-FileHash -Algorithm SHA256 $glb).Hash)
Write-Output ('right_arm_children=' + (($children.name) -join ','))
Write-Output ('anonymous_right_arm_details=' + $anonymous.Count)
Write-Output ('source_has_old_finger_rods=' + ($source -match 'for f in 3:link\(arm,Vector3\(-\.032\+f\*\.026,-\.50,\.052\)'))
