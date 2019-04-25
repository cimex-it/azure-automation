# Script for removing metrics data from diagnostics storage accounts

# Keep log data for the following amount of days
$daysToKeep = 60

$account = Get-AutomationConnection -Name AzureRunAsConnection
Login-AzAccount -ServicePrincipal -Tenant $account.TenantID -ApplicationId $account.ApplicationID -CertificateThumbprint $account.CertificateThumbprint -Environment "AzureCloud"

$removeDate = (Get-Date).AddDays(-$daysToKeep-10).ToString('yyyyMMdd')

$storageAccounts = Get-AzStorageAccount

foreach ($sa in $storageAccounts) {
    $saContext = (Get-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName).Context
    $storageTable = Get-AzStorageTable -Context $saContext | where {$_.Name -match "^WADMetrics.*(\d\d\d\d\d\d\d\d)$" -and $Matches[1] -lt $removeDate}
    $storageTable | Remove-StorageTable -Context $saContext
}