# Script for removing metrics data from diagnostics storage accounts

# Keep log data for the following amount of days
$daysToKeep = 30

$account = Get-AutomationConnection -Name AzureRunAsConnection
Login-AzAccount -ServicePrincipal -Tenant $account.TenantID -ApplicationId $account.ApplicationID -CertificateThumbprint $account.CertificateThumbprint -Environment "AzureCloud"

$removeDate = (Get-Date).AddDays(-$daysToKeep-10).ToString('yyyyMMdd')

$storageAccounts = Get-AzStorageAccount | where {$_.SKUName -eq "StandardLRS"}

foreach ($sa in $storageAccounts) {
    $saContext = (Get-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName).Context
    Get-AzStorageTable -Context $saContext | where {$_.Name -match "^WADMetrics.*(\d\d\d\d\d\d\d\d)$" -and $Matches[1] -lt $removeDate} | Remove-AzStorageTable -Context $saContext -Force -Verbose
}