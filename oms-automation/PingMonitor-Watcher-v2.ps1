function Ping-Monitor 
{
    [CmdletBinding(ConfirmImpact='Low')]
    Param(
        [int]$Interval = 30,
        [string]$VariableName = 'PingMonitorDevices',
        [Switch]$RawOutput = $false
    )

    $timeout = 2500

    try{
        Get-AutomationVariable -Name $VariableName -ErrorAction Stop
    } catch {
        Write-Output "Please create an Automation Variable named '$VariableName' before continuing"
        throw "Missing Automation Variable '$VariableName'"
    }

    $networkDevicesJson = Get-AutomationVariable -Name $VariableName
    $networkDevices = ConvertFrom-Json $networkDevicesJson

    $IpTotal = $networkDevices.Count

    Get-Event -SourceIdentifier "ID-Ping*" | Remove-Event
    Get-EventSubscriber -SourceIdentifier "ID-Ping*" | Unregister-Event

    $networkDevices | ForEach-Object {

        [string]$VarName = "Ping_" + $_.IPAddress

        New-Variable -Name $VarName -Value (New-Object System.Net.NetworkInformation.Ping)

        Register-ObjectEvent -InputObject (Get-Variable $VarName -ValueOnly) -EventName PingCompleted -SourceIdentifier "ID-$VarName"

        (Get-Variable $VarName -ValueOnly).SendAsync($_.IPAddress,$timeout,$VarName)

        Remove-Variable $VarName

        try
        {

            $pending = (Get-Event -SourceIdentifier "ID-Ping*").Count

        } 
        catch [System.InvalidOperationException]
        {
            $pending = 0
        }

        $index = [array]::indexof($networkDevices,$_)

        Write-Progress -Activity "Sending ping to" -Id 1 -status $_.IPAddress -PercentComplete (($index / $IpTotal)  * 100)

        $percentComplete = ($($index - $pending), 0 | Measure-Object -Maximum).Maximum

        Write-Progress -Activity "ICMP requests pending" -Id 2 -ParentId 1 -Status ($index - $pending) -PercentComplete ($percentComplete/$IpTotal * 100)

        Start-Sleep -Milliseconds $Interval
    }

    Write-Progress -Activity "Done sending ping requests" -Id 1 -Status 'Waiting' -PercentComplete 100 

    while ($pending -lt $IpTotal) {

        Wait-Event -SourceIdentifier "ID-Ping*" | Out-Null

        Start-Sleep -Milliseconds 10

        try
        {

            $pending = (Get-Event -SourceIdentifier "ID-Ping*").Count

        }
        catch [System.InvalidOperationException]
        {
            $pending = 0
        }

        $percentComplete = ($($IpTotal - $pending), 0 | Measure-Object -Maximum).Maximum

        Write-Progress -Activity "ICMP requests pending" -Id 2 -ParentId 1 -Status ($IpTotal - $pending) -PercentComplete ($percentComplete/$IpTotal * 100)
    }

    Write-Progress -Completed -Id 2 -ParentId 1 -Activity "Completed"
    Write-Progress -Completed -Id 1 -Activity "Completed"

     $Reply = @()

    if ($RawOutput)
    {
        Get-Event -SourceIdentifier "ID-Ping*" | foreach { 
            if ($_.SourceEventArgs.Reply.Status -eq "Success")
            {
                $Reply += $_.SourceEventArgs.Reply
            }
            Unregister-Event $_.SourceIdentifier
            Remove-Event $_.SourceIdentifier
        }
    }
    else
    {
        Get-Event -SourceIdentifier "ID-Ping*" | ForEach-Object { 
            if ($_.SourceEventArgs.Reply.Status -eq "Success")
            {
                $pinger = @{
                    IPAddress = $_.SourceEventArgs.Reply.Address.IPAddressToString
                    ResponseTime = $_.SourceEventArgs.Reply.RoundtripTime
                }
                $Reply += New-Object PSObject -Property $pinger
            }
            Unregister-Event $_.SourceIdentifier
            Remove-Event $_.SourceIdentifier
        }
    }

    if ($Reply.Count -eq 0)
    {
        Write-Verbose "Ping-IPRange : No IP address responded" -Verbose
    }

    return $Reply
}

$result = Ping-Monitor -Interval 10
$resultJson = $result | ConvertTo-Json

Invoke-AutomationWatcherAction -Data $resultJson
