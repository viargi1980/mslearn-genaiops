$experiment = "baseline"
$jsonPath = "experiments/$experiment/agent-responses.json"
$csvPath = "experiments/$experiment/evaluation.csv"

(Get-Content $jsonPath -Raw | ConvertFrom-Json).test_results |
    ForEach-Object {
        [PSCustomObject]@{
            test_prompt          = $_.test_name
            agent_response_excerpt = $_.response.Substring(0, [Math]::Min(160, $_.response.Length))
            intent_resolution    = ""
            relevance            = ""
            groundedness         = ""
            comments             = ""
        }
    } |
    Export-Csv $csvPath -NoTypeInformation -Encoding utf8

Write-Host "Creado: $csvPath"