# --------------------
# Author: Cody Hussey
# Company: Yubico
# --------------------

# Get engineer name for tagging, and customer for unique identifier
$Engineer = Read-Host -Prompt 'Enter your first name for tagging purposes'
$Customer = Read-Host -Prompt 'Enter customer ID <= 6 characters'
$Customer = $Customer.ToLower()

if ($Engineer -and $Customer)
{
    Write-Host "First up, a resource group for $customer..."
}
else {
    Write-Warning 'Values cannot be null.'
    break
}

# Check to see if customer ID already exists
if ((Get-AzResourceGroup | where resourcegroupname -like $Customer) -ne $null)
{
    Write-Warning 'That customer ID already exists.'
    break
}

# Create Resource Group, deploy resources
New-AzResourceGroup -Name $Customer -Location "East US" -Tag @{Engineer="$Engineer"}
Write-Host "Kicking off the resource deployment to the new group which will take ~15 minutes."
New-AzResourceGroupDeployment -Name 'init' -ResourceGroupName $Customer -TemplateUri 'https://raw.githubusercontent.com/huzzeytech/az-deploy/master/azuredeploy.json' -TemplateParameterObject @{envid="$Customer"}

# Azure Automation AD/CA Registration
Write-Host "Finished resource deployment, preparing Azure Automation for Registration."

# Parameters for Compilation Jobs
$Params = @{"credname"="$Customer-yubi"}
$ConfigData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $True
        }
    )
}

# Import DSC Modules
New-AzAutomationModule -Name ActiveDirectoryCSDsc -ContentLinkUri "https://github.com/huzzeytech/az-deploy/raw/master/etc/ActiveDirectoryCSDsc.zip" -ResourceGroupName "infra" -AutomationAccountName "$Customer-auto"
do {
    $StatusMod1 = Get-AzAutomationModule -ResourceGroupName "infra" -AutomationAccountName "$Customer-auto" | Where-Object {$_.Name -eq "ActiveDirectoryCSDsc"} | Select-Object -ExpandProperty "ProvisioningState"
    Start-Sleep -Seconds 3
} until ($StatusMod1 -eq "Succeeded")

New-AzAutomationModule -Name xPSDesiredStateConfiguration -ContentLinkUri "https://github.com/huzzeytech/az-deploy/raw/master/etc/xPSDesiredStateConfiguration.zip" -ResourceGroupName "infra" -AutomationAccountName "$Customer-auto"
do {
    $StatusMod2 = Get-AzAutomationModule -ResourceGroupName "infra" -AutomationAccountName "$Customer-auto" | Where-Object {$_.Name -eq "xPSDesiredStateConfiguration"} | Select-Object -ExpandProperty "ProvisioningState"
    Start-Sleep -Seconds 3
} until ($StatusMod2 -eq "Succeeded")

# Compilation Jobs
Start-AzAutomationDscCompilationJob -ResourceGroupName 'infra' -AutomationAccountName "$Customer-auto" -ConfigurationName "CertAuthConfig" -ConfigurationData $ConfigData -Parameters $Params
do {
    $StatusJob1 = Get-AzAutomationDscCompilationJob -ResourceGroupName "infra" -AutomationAccountName "$Customer-auto" -ConfigurationName "CertAuthConfig" | Select-Object -ExpandProperty "Status"
    Start-Sleep -Seconds 3
} until ($StatusJob1 -eq "Completed")

Start-AzAutomationDscCompilationJob -ResourceGroupName 'infra' -AutomationAccountName "$Customer-auto" -ConfigurationName 'ClientConfig' -ConfigurationData $ConfigData
do {
    $StatusJob2 = Get-AzAutomationDscCompilationJob -ResourceGroupName "infra" -AutomationAccountName "$Customer-auto" -ConfigurationName "ClientConfig" | Select-Object -ExpandProperty "Status"
    Start-Sleep -Seconds 3
} until ($StatusJob2 -eq "Completed")

# Register Nodes
# DC/CA
Write-Host "Waiting 5 minutes before registering machines."
Start-Sleep -Seconds 300
Write-Host "Registering DC/CA..."
Register-AzAutomationDscNode -AutomationAccountName "$Customer-auto" -ResourceGroupName "infra" -AzureVMResourceGroup "$Customer" -AzureVMName "$Customer-dc1" -ActionAfterReboot "ContinueConfiguration" -RebootNodeIfNeeded $True -AllowModuleOverwrite $True -NodeConfigurationName "CertAuthConfig.localhost"
# Windows 10 Client
Write-Host "Registering Client..."
Register-AzAutomationDscNode -AutomationAccountName "$Customer-auto" -ResourceGroupName "infra" -AzureVMResourceGroup "$Customer" -AzureVMName "$Customer-client" -ActionAfterReboot "ContinueConfiguration" -RebootNodeIfNeeded $True -AllowModuleOverwrite $True -NodeConfigurationName "ClientConfig.localhost"
# After reg finished...wait 15 min or poll for DSC Status

Write-Host "Successful deployment. Please RDP to your Windows 10 client to confirm configuration: $customer.yubi.fun"