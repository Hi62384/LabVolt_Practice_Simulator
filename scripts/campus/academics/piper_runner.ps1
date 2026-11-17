param(
    [Parameter(Mandatory=$true)][string]$Piper,
    [Parameter(Mandatory=$true)][string]$Model,
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][int]$Speaker,
    [Parameter(Mandatory=$true)][string]$LengthScale,
    [Parameter(Mandatory=$true)][string]$SentenceSilence
)
$ErrorActionPreference='Stop'
if (!(Test-Path -LiteralPath $Piper) -or !(Test-Path -LiteralPath $Model) -or !(Test-Path -LiteralPath $InputPath)) { exit 2 }
if ($LengthScale -notmatch '^\d+(\.\d+)?$' -or $SentenceSilence -notmatch '^\d+(\.\d+)?$') { exit 2 }
Get-Content -Raw -Encoding UTF8 -LiteralPath $InputPath | & $Piper --model $Model --config "$Model.json" --output_file $OutputPath --speaker $Speaker --length_scale $LengthScale --sentence_silence $SentenceSilence --quiet
exit $LASTEXITCODE
