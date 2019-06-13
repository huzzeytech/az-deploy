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

# Create Resource Group, and deploy resources from template
New-AzResourceGroup -Name $Customer -Location "East US" -Tag @{Engineer="$Engineer"}
Write-Host "Kicking off the resource deployment to the new group which will take ~15 minutes."
New-AzResourceGroupDeployment -Name 'init' -ResourceGroupName $Customer -TemplateUri 'https://raw.githubusercontent.com/huzzeytech/az-deploy/master/azuredeploy.json' -TemplateParameterObject @{envid="$Customer"}

# Azure Automation AD/CA Registration
Write-Host "Finished resource deployment, now registering machines to Azure Automation for configuration."

$Params = @{"credname"="$Customer-yubi"}
$ConfigData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $True
        }
    )
}

Start-AzAutomationDscCompilationJob -ResourceGroupName 'infra' -AutomationAccountName 'yubi-auto' -ConfigurationName "$Customer-CertAuthConfig" -ConfigurationData $ConfigData -Parameters $Params
Register-AzAutomationDscNode -AutomationAccountName "yubi-auto" -ResourceGroupName "infra" -AzureVMResourceGroup "$Customer" -AzureVMName "$Customer-dc1" -ActionAfterReboot "ContinueConfiguration" -RebootNodeIfNeeded $True  -NodeConfigurationName "$Customer-CertAuthConfig.localhost"

# Azure Automation Windows 10 Client Registration
Start-AzAutomationDscCompilationJob -ResourceGroupName 'infra' -AutomationAccountName 'yubi-auto' -ConfigurationName '$Customer-ClientConfig' -ConfigurationData $ConfigData
Register-AzAutomationDscNode -AutomationAccountName "yubi-auto" -ResourceGroupName "infra" -AzureVMResourceGroup "$Customer" -AzureVMName "$Customer-client" -ActionAfterReboot "ContinueConfiguration" -RebootNodeIfNeeded $True  -NodeConfigurationName "$Customer-ClientConfig.localhost"

Write-Host "Successful registration. Please RDP to your Windows 10 client to confirm configuration: $customer.yubi.fun"