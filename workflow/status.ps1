param([Parameter(Mandatory = $true)][string]$Session)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/workflow-review.ps1')
Show-WorkflowStatus $Session
