
$VariableName = 'PingMonitorDevices'

$storageAccount = "cimexmonitoringdata01"
$resourceGroup = "oms-rg"
$storageTableName = "monitoringconfig"
$partitionKey = "networkDevice"

$account = Get-AutomationConnection -Name AzureRunAsConnection
Login-AzAccount -ServicePrincipal -Tenant $account.TenantID -ApplicationId $account.ApplicationID -CertificateThumbprint $account.CertificateThumbprint -Environment "AzureCloud"

# Read group sync config from Azure Table storage
$saContext = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount).Context
$storageTable = (Get-AzStorageTable -Name $storageTableName -Context $saContext).CloudTable
$networkDevices = Get-AzTableRow -Table $storageTable -partitionKey $partitionKey

$networkDevicesJson = ($networkDevices | ConvertTo-Json).ToString()

try{
    Get-AutomationVariable -Name $VariableName -ErrorAction Stop
} catch {
    Write-Output "Please create an Automation Variable named '$VariableName' before continuing"
    throw "Missing Automation Variable '$VariableName'"
}

$networkDevicesJson

Set-AutomationVariable -Name $VariableName -Value $networkDevicesJson