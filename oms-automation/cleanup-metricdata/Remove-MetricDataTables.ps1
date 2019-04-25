<#

    .DESCRIPTION

      Script for removing metrics data from diagnostics storage accounts    
    
      This script removes all Storage Tables created by guest-level monitoring older than a specified number of days.
      It goes through all storage accounts in a subscription.

    .NOTES

        AUTHOR: Ondrej Vaclavu

        LASTEDIT: Apr 25, 2019

#>

$Params = @{
    # Keep log data for the following number of days
    [int]$DaysToKeep = 30
}

# Calculate remove date
$removeDate = (Get-Date).AddDays(-$DaysToKeep-10).ToString('yyyyMMdd')

# Login to Azure
$account = Get-AutomationConnection -Name AzureRunAsConnection
Login-AzAccount -ServicePrincipal -Tenant $account.TenantID -ApplicationId $account.ApplicationID -CertificateThumbprint $account.CertificateThumbprint -Environment "AzureCloud"

#List all Standard LRS storage accounts
$storageAccounts = Get-AzStorageAccount | where {$_.Sku.Name -eq "StandardLRS"}

# Go through all storage acounts and remove metric tables
foreach ($sa in $storageAccounts) {
    $saContext = (Get-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName).Context
    $storageTables = Get-AzStorageTable -Context $saContext | where {$_.Name -match "^WADMetrics.*(\d\d\d\d\d\d\d\d)$" -and $Matches[1] -lt $removeDate}
    $storageTables | Remove-AzStorageTable -Context $saContext -Force -Verbose
}