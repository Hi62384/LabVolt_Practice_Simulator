$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$source = Join-Path $project 'scripts'
$files = Get-ChildItem -LiteralPath $source -Recurse -Filter '*.gd' -File | Where-Object { $_.FullName -notmatch '[\\/]review[\\/]' }
$violations = foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'BILLBOARD_(ENABLED|FIXED_Y)|\.billboard\s*=|\.look_at\(' -and $lines[$i] -notmatch 'camera\.look_at\(|_camera\.look_at\(|preview_camera\.look_at\(|inspect_camera\.look_at\(|cam\.look_at\(') {
            '{0}:{1}: {2}' -f $file.FullName, ($i + 1), $lines[$i].Trim()
        }
    }
}
if ($violations) { $violations | ForEach-Object { Write-Error $_ }; exit 1 }
'No billboard or dynamic look-at text paths found in active scripts.'
