[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [string]$DestinationPath = "experiments/automated/evaluation-results-classroom-40.jsonl"
)

$ErrorActionPreference = 'Stop'

function Find-FirstProperty {
    param(
        [object]$Node,
        [string]$PropertyName
    )

    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) {
        return $null
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) {
            $value = Find-FirstProperty -Node $item -PropertyName $PropertyName
            if ($null -ne $value) { return $value }
        }
        return $null
    }

    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -ieq $PropertyName) {
            return $property.Value
        }
    }

    foreach ($property in $Node.PSObject.Properties) {
        $value = Find-FirstProperty -Node $property.Value -PropertyName $PropertyName
        if ($null -ne $value) { return $value }
    }

    return $null
}

function Find-GroundednessEvaluator {
    param([object]$Node)

    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) {
        return $null
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) {
            $value = Find-GroundednessEvaluator -Node $item
            if ($null -ne $value) { return $value }
        }
        return $null
    }

    $name = $Node.PSObject.Properties['name']
    if ($null -ne $name -and $name.Value -match '^groundedness$') {
        return $Node
    }

    foreach ($property in $Node.PSObject.Properties) {
        $value = Find-GroundednessEvaluator -Node $property.Value
        if ($null -ne $value) { return $value }
    }

    return $null
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Results file not found: $SourcePath"
}

$destinationDirectory = Split-Path -Parent $DestinationPath
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

# The usual path starts in Downloads and is moved into experiments. During a
# classroom rerun, however, the file may already be stored there. Treat that
# as an analysis-only run; never overwrite a different existing result.
$sourceResolvedPath = (Resolve-Path -LiteralPath $SourcePath).Path
if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
    $destinationResolvedPath = (Resolve-Path -LiteralPath $DestinationPath).Path
    if ($sourceResolvedPath -ne $destinationResolvedPath) {
        throw "Destination already exists: $DestinationPath. Choose a new name; this script never overwrites results."
    }

    Write-Host "Results already in destination; analyzing without moving them."
}
else {
    Move-Item -LiteralPath $SourcePath -Destination $DestinationPath
    Write-Host "Moved results to: $DestinationPath"
}

$script:lineNumber = 1
$records = Get-Content -LiteralPath $DestinationPath | Where-Object { $_.Trim() } | ForEach-Object {
    $record = $_ | ConvertFrom-Json
    $groundedness = Find-GroundednessEvaluator -Node $record
    $groundednessJson = if ($null -ne $groundedness) {
        $groundedness | ConvertTo-Json -Depth 20 -Compress
    } else {
        ''
    }

    # Do not search the serialized trace for the word "fail": it can appear
    # in the model response itself (for example, "waterproofing fails").
    # Use the evaluator's top-level, structured verdict instead.
    $scoreProperty = if ($null -ne $groundedness) { $groundedness.PSObject.Properties['score'] } else { $null }
    $thresholdProperty = if ($null -ne $groundedness) { $groundedness.PSObject.Properties['threshold'] } else { $null }
    $passedProperty = if ($null -ne $groundedness) { $groundedness.PSObject.Properties['passed'] } else { $null }
    $score = if ($null -ne $scoreProperty) { [double]$scoreProperty.Value } else { $null }
    $threshold = if ($null -ne $thresholdProperty) { [double]$thresholdProperty.Value } else { $null }
    $passed = if ($null -ne $passedProperty) { [bool]$passedProperty.Value } else { $null }
    $isCandidate = ($passed -eq $false) -or ($null -ne $score -and $null -ne $threshold -and $score -lt $threshold)

    [pscustomobject]@{
        Line         = $script:lineNumber
        Query        = Find-FirstProperty -Node $record -PropertyName 'query'
        GroundTruth  = Find-FirstProperty -Node $record -PropertyName 'ground_truth'
        Score        = $score
        Threshold    = $threshold
        Passed       = $passed
        Groundedness = $groundednessJson
        Candidate    = $isCandidate
        RawJson      = $_
    }
    $script:lineNumber++
}

$candidates = $records | Where-Object { $_.Candidate }
$candidatePath = Join-Path $destinationDirectory 'groundedness-review-candidates.jsonl'
$candidates.RawJson | Set-Content -LiteralPath $candidatePath -Encoding utf8

Write-Host "Records found: $($records.Count)"
Write-Host "Groundedness review candidates: $($candidates.Count)"
Write-Host "Candidate rows saved to: $candidatePath"

$candidates | Select-Object Line, Query, GroundTruth, Score, Threshold, Passed, Groundedness | Format-List
