$CustomDomain = $Args[0] + "-yubi.fun"

Install-WindowsFeature -name AD-Domain-Services, rsat-adds -IncludeAllSubFeature
Install-ADDSForest -DomainName $CustomDomain -InstallDNS:$true -safemodeadministratorpassword (convertto-securestring "Testing123!" -asplaintext -force) -NoRebootOnCompletion:$true
