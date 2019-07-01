# --------------------
# Author: Cody Hussey
# Company: Yubico
# --------------------

# Delete Resource Group
$Customer = Read-Host -Prompt 'Enter customer ID'
$Customer = $Customer.ToLower()
Get-AzResourceGroup -Name $Customer | Remove-AzResourceGroup -Verbose -Force

# Delete Automation Account
Remove-AzAutomationAccount -Name "$Customer-auto" -Force -ResourceGroupName "infra"

# Delete DNS Name
Get-AzDnsRecordSet -ResourceGroupName "infra" -ZoneName "yubi.fun" -RecordType A -Name $Customer | Remove-AzDnsRecordSet

Write-Host "The $customer environment was successfully deleted."