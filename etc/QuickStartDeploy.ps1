# --------------------
# Author: Cody Hussey
# Company: Yubico
# --------------------

# Get engineer name for tagging, and customer for unique identifier
$Engineer = Read-Host -Prompt 'What is your first name?'
$Customer = Read-Host -Prompt 'Enter customer ID - less than 6 characters'
if ($Engineer -and $Customer)
{
    Write-Host "Deploying $customer environment for $Engineer..."
}
else {
    Write-Warning 'Values cannot be null.'
    break
}

# Create Resource Group, and deploy resources from template
New-AzResourceGroup -Name $Customer -Location "East US" -Tag @{Engineer="$Engineer"}
Write-Host "Starting deployment, will take ~20 minutes. Progress may be tracking in Azure Portal"
New-AzResourceGroupDeployment -Name 'init' -ResourceGroupName $Customer -TemplateUri 'https://raw.githubusercontent.com/huzzeytech/az-deploy/master/azuredeploy.json' -TemplateParameterObject @{envid="$Customer"}
Write-Host "Successful Deployment..."

# Azure Automation Registration
$Params = @{"credname"="$Customer-yubi"}
$ConfigData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $True
        }
    )
}

Start-AzAutomationDscCompilationJob -ResourceGroupName 'infra' -AutomationAccountName 'yubi-auto' -ConfigurationName 'CertAuthConfig' -ConfigurationData $ConfigData -Parameters $Params

Register-AzAutomationDscNode -AutomationAccountName "yubi-auto" -ResourceGroupName "infra" -AzureVMResourceGroup "$Customer" -AzureVMName "$Customer-ca" -ActionAfterReboot "ContinueConfiguration" -NodeConfigurationName "CertAuthConfig.localhost"