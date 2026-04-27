$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

$copies = @(
    @{ Source = "common\rpc.lua"; Target = "control_hub\rpc.lua" },
    @{ Source = "common\rpc.lua"; Target = "airspeed_node\rpc.lua" },
    @{ Source = "common\rpc.lua"; Target = "actuator_node\rpc.lua" },
    @{ Source = "common\airspeed.lua"; Target = "airspeed_node\airspeed.lua" },
    @{ Source = "common\actuator.lua"; Target = "actuator_node\actuator.lua" }
)

foreach ($copy in $copies) {
    $source = Join-Path $root $copy.Source
    $target = Join-Path $root $copy.Target
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Host "$($copy.Source) -> $($copy.Target)"
}
