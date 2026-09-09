<##
.SYNOPSIS
Creates a synthetic evaluation.csv from an agent-responses.json file.

.DESCRIPTION
The scores and comments are randomly generated for classroom/demo use only.
They are not a quality evaluation of the agent's responses.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Experiment
)

$ErrorActionPreference = 'Stop'

$jsonPath = Join-Path "experiments/$Experiment" 'agent-responses.json'
$csvPath = Join-Path "experiments/$Experiment" 'evaluation.csv'

if (-not (Test-Path $jsonPath)) {
    throw "No se encontró '$jsonPath'. Ejecuta primero: python src/tests/run_batch_tests.py $Experiment"
}

$comments = @(
    'Clear and comprehensive response',
    'Good safety focus and practical guidance',
    'Helpful and actionable answer',
    'Relevant response with useful detail',
    'Concise response that addresses the request'
)

(Get-Content $jsonPath -Raw | ConvertFrom-Json).test_results |
    ForEach-Object {
        $response = [string]$_.response
        $excerpt = $response.Substring(0, [Math]::Min(160, $response.Length))

        [PSCustomObject]@{
            test_prompt            = $_.test_name
            agent_response_excerpt = $excerpt
            intent_resolution      = Get-Random -Minimum 3 -Maximum 6
            relevance               = Get-Random -Minimum 3 -Maximum 6
            groundedness            = Get-Random -Minimum 3 -Maximum 6
            comments                = Get-Random -InputObject $comments
        }
    } |
    Export-Csv $csvPath -NoTypeInformation -Encoding utf8

Write-Host "Creado: $csvPath"
Write-Warning 'Las puntuaciones y comentarios son sintéticos y aleatorios; no representan una evaluación real.'
