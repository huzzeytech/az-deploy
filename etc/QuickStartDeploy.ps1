# --------------------
# Author: Cody Hussey
# Company: Yubico
# --------------------

# Get engineer name for tagging, and customer for unique identifier
$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
$Engineer = Read-Host -Prompt 'Enter your first name for tagging purposes'
$Customer = Read-Host -Prompt 'Enter customer ID <= 6 characters'
$Customer = $Customer.ToLower()
$Password = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | Sort-Object {Get-Random})[0..12] -join ''

if ($Engineer -and $Customer)
{
    Write-Host "First up, a resource group for $customer..."
}
else {
    Write-Warning 'Values cannot be null.'
    break
}

# Check to see if customer ID already exists
if ($null -ne (Get-AzResourceGroup | Where-Object resourcegroupname -like $Customer))
{
    Write-Warning 'That customer ID already exists.'
    break
}

# Create Resource Group, deploy resources
New-AzResourceGroup -Name $Customer -Location "East US" -Tag @{Engineer="$Engineer"}
Write-Host "Kicking off the resource deployment to the new group which will take ~55 minutes."
New-AzResourceGroupDeployment -Name 'init' -ResourceGroupName $Customer -TemplateUri 'https://raw.githubusercontent.com/huzzeytech/az-deploy/master/azuredeploy.json' -TemplateParameterObject @{envid="$Customer";adminPassword="$Password"}

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

Start-AzAutomationDscCompilationJob -ResourceGroupName 'infra' -AutomationAccountName "$Customer-auto" -ConfigurationName 'ClientConfig' -ConfigurationData $ConfigData -Parameters $Params
do {
    $StatusJob2 = Get-AzAutomationDscCompilationJob -ResourceGroupName "infra" -AutomationAccountName "$Customer-auto" -ConfigurationName "ClientConfig" | Select-Object -ExpandProperty "Status"
    Start-Sleep -Seconds 3
} until ($StatusJob2 -eq "Completed")

# Register Nodes
# DC/CA
Write-Host "Waiting 3 minutes before registering machines."
Start-Sleep -Seconds 180
Write-Host "Registering DC/CA..."
Register-AzAutomationDscNode -AutomationAccountName "$Customer-auto" -ResourceGroupName "infra" -AzureVMResourceGroup "$Customer" -AzureVMName "$Customer-dc1" -ActionAfterReboot "ContinueConfiguration" -RebootNodeIfNeeded $True -AllowModuleOverwrite $True -NodeConfigurationName "CertAuthConfig.localhost"
# Windows 10 Client
Write-Host "Registering Client..."
Register-AzAutomationDscNode -AutomationAccountName "$Customer-auto" -ResourceGroupName "infra" -AzureVMResourceGroup "$Customer" -AzureVMName "$Customer-client" -ActionAfterReboot "ContinueConfiguration" -RebootNodeIfNeeded $True -AllowModuleOverwrite $True -NodeConfigurationName "ClientConfig.localhost"
# Post Registration, wait 15 minutes to accomodate validation of resources
Start-Sleep -Seconds 1080
Write-Host "Restarting VMs..."
Get-AzVM -ResourceGroupName "$Customer" | Restart-AzVM
Start-Sleep -Seconds 180

# Calculate Time for Deployment
$StopWatch.Stop()
$TotalTime = [math]::Round($StopWatch.Elapsed.TotalMinutes,2)
Write-Host "This deployment took $TotalTime minutes to run. Please RDP to your Windows 10 client: $customer.yubi.fun"
