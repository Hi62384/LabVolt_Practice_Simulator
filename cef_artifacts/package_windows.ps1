param(
    [Parameter(Mandatory=$true)]
    [string]$ExportDirectory
)

$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'windows'))
$destination = [IO.Path]::GetFullPath($ExportDirectory)
if (-not [IO.Directory]::Exists($source)) { throw 'CEF Windows runtime is missing.' }
if (-not [IO.Directory]::Exists($destination)) { throw 'Export directory does not exist.' }
if (-not [IO.File]::Exists((Join-Path $destination 'LabVolt.exe'))) { throw 'LabVolt.exe is missing from the export directory.' }

Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -in @('.dll','.exe','.pak','.dat','.bin','.json') } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination $_.Name) -Force
}
$locales = Join-Path $source 'locales'
if ([IO.Directory]::Exists($locales)) {
    $targetLocales = Join-Path $destination 'locales'
    [IO.Directory]::CreateDirectory($targetLocales) | Out-Null
    Get-ChildItem -LiteralPath $locales -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetLocales $_.Name) -Force
    }
}
