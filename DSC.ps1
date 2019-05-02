Configuration rootca
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,
 
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds
 
    )
 
     Import-DscResource -ModuleName xAdcsDeployment, PSDesiredStateConfiguration
 
     Node localhost
     {
 
        # Install the ADCS Certificate Authority
        WindowsFeature ADCSCA {
            Name = 'ADCS-Cert-Authority'
            Ensure = 'Present'
        }
        
        # Configure the CA as Standalone Root CA
        xADCSCertificationAuthority ConfigCA
        {
            Ensure = 'Present'
            # Credential = $LocalAdminCredential
            CAType = 'EnterpriseRootCA'
            CACommonName = $Node.CACommonName
            CADistinguishedNameSuffix = $Node.CADistinguishedNameSuffix
            ValidityPeriod = 'Years'
            ValidityPeriodUnits = 20
            CryptoProviderName = 'RSA#Microsoft Software Key Storage Provider'
            HashAlgorithmName = 'SHA256'
            KeyLength = 4096
            DependsOn = '[WindowsFeature]ADCSCA' 
        }
 
            WindowsFeature RSAT-ADCS 
        { 
            Ensure = 'Present' 
            Name = 'RSAT-ADCS' 
            DependsOn = '[WindowsFeature]ADCSCA' 
        } 
        WindowsFeature RSAT-ADCS-Mgmt 
        { 
            Ensure = 'Present' 
            Name = 'RSAT-ADCS-Mgmt' 
            DependsOn = '[WindowsFeature]ADCSCA' 
        } 
     }
  }