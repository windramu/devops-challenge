// Module input parameters
param keyVaultName string
param secretNames array
param location string = resourceGroup().location
param passwordLength int = 24

// Create a user-assigned managed identity 
// used for authenticating against Azure resources 
// during the execution of the PowerShell script.
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'script-identity'
  location: location
}

// Establish a reference to an existing KeyVault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

// Grant managed-identity access to KeyVault
resource keyVaultAccessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [ {
        tenantId: subscription().tenantId
        objectId: scriptIdentity.properties.principalId
        permissions: {
          secrets: ['set', 'get', 'list']
        }
      } ]
  }
}

// Setup a PowerShell deployment script to generate passwords
// assign managed identity created earlier to authenticate with KeyVault.
resource passwordScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'generateSecrets'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '7.0'
    retentionInterval: 'P1D'
    scriptContent: '''
      param(
          [string] $KeyVaultName,
          [string[]] $SecretNames,
          [int] $PasswordLength
      )

      $results = @{}

      foreach ($secretName in $SecretNames) {

          # Try to get the existing secret
          $existingSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -ErrorAction SilentlyContinue

          # Generate a new password if the secret doesn't exist
          if ($null -eq $existingSecret) {

              # define character set
              $charSet = @()
              $charSet += 65..90                              # include uppercase
              $charSet += 97..122                             # include lowercase
              $charSet += 48..57                              # include numbers
              $charSet += 33..47 + 58..64 + 91..96 + 123..126 # include special characters

              $password = -join ($charSet | Get-Random -Count $PasswordLength | ForEach-Object {[char]$_})
              $secureStringPassword = ConvertTo-SecureString $password -AsPlainText -Force
              Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -SecretValue $secureStringPassword | Out-Null
              Write-Output "New password generated and stored in Key Vault for $secretName."
           } else {
               Write-Output "Existing password found in Key Vault for $secretName."
           }

           # Store the secret name in results (could also store the value if needed)
           $results[$secretName] = if ($existingSecret) { $existingSecret.Id } else { "Generated" }
       }

       # Output the results
       return @{ secrets = $results }
    '''
    arguments: '-KeyVaultName ${keyVaultName} -SecretNames ${join(secretNames, ',')} -PasswordLength ${passwordLength}'
  }
}

// Construct a result object that can be referenced in subsequent bicep modules
output results object = reduce(secretNames, {}, (acc, key) => union(acc, { '${key}': key }))
