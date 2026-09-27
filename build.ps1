# =====================================================================
# build.ps1 — Compila el informe a PDF en Windows (PowerShell)
#   .\build.ps1                 -> entrega TB1
#   .\build.ps1 -Milestone av2  -> entrega AV2
# Requisitos: Pandoc 3.x y MiKTeX (o TeX Live) en el PATH.
# =====================================================================
param(
  [string]$Milestone = "tb1",
  [string]$Nrc = "7742",
  [string]$Startup = "dymbia"
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path dist | Out-Null
$out = "dist/upc-pre-202620-1asi0729-$Nrc-$Startup-report-$Milestone.pdf"
pandoc --defaults=config/build.yaml -o $out
if ($LASTEXITCODE -ne 0) { throw "Pandoc terminó con errores." }
Write-Host "PDF generado: $out" -ForegroundColor Green
