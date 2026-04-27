$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

$copies = @(
    @{ Source = "common\rpc.lua"; Target = "control_hub\rpc.lua" },
    @{ Source = "common\rpc.lua"; Target = "airspeed_node\rpc.lua" },
    @{ Source = "common\rpc.lua"; Target = "actuator_node\rpc.lua" },
    @{ Source = "common\rpc.lua"; Target = "gnss\rpc.lua" },
    @{ Source = "common\pid.lua"; Target = "control_hub\pid.lua" },
    @{ Source = "common\airspeed.lua"; Target = "airspeed_node\airspeed.lua" },
    @{ Source = "common\actuator.lua"; Target = "actuator_node\actuator.lua" },
    @{ Source = "common\gnss.lua"; Target = "gnss\gnss.lua" }
)

foreach ($copy in $copies) {
    $source = Join-Path $root $copy.Source
    $target = Join-Path $root $copy.Target
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Host "$($copy.Source) -> $($copy.Target)"
}

$displayTarget = Join-Path $root "control_hub\display"
New-Item -ItemType Directory -Path $displayTarget -Force | Out-Null

Get-ChildItem -LiteralPath (Join-Path $root "display") -Filter "*.lua" | ForEach-Object {
    $target = Join-Path $displayTarget $_.Name
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    Write-Host "display\$($_.Name) -> control_hub\display\$($_.Name)"
}
