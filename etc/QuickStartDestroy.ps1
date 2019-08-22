# --------------------
# Author: Cody Hussey
# Company: Yubico
# --------------------

$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

# Delete Resource Group
$Customer = Read-Host -Prompt 'Enter customer ID'
$Customer = $Customer.ToLower()
try{
    Get-AzResourceGroup -Name $Customer | Remove-AzResourceGroup -Verbose -Force
}
catch
{

}

# Delete Automation Account
Remove-AzAutomationAccount -Name "$Customer-auto" -Force -ResourceGroupName "infra"

# Delete DNS Name
Get-AzDnsRecordSet -ResourceGroupName "infra" -ZoneName "yubi.fun" -RecordType A -Name $Customer | Remove-AzDnsRecordSet

$StopWatch.Stop()
$TotalTime = [math]::Round($StopWatch.Elapsed.TotalMinutes,2)
Write-Host "The $customer environment was successfully deleted in $TotalTime minutes."