#
# Module manifest for module 'SharePointDsc'
#
# Generated by: Microsoft Corporation
#
# Generated on: 20/06/2018
#

@{

  # Script module or binary module file associated with this manifest.
  # RootModule = ''

  # Version number of this module.
  ModuleVersion     = '3.7.0.0'

  # ID used to uniquely identify this module
  GUID              = '6c1176a0-4fac-4134-8ca2-3fa8a21a7b90'

  # Author of this module
  Author            = 'Microsoft Corporation'

  # Company or vendor of this module
  CompanyName       = 'Microsoft Corporation'

  # Copyright statement for this module
  Copyright         = '(c) 2015-2018 Microsoft Corporation. All rights reserved.'

  # Description of the functionality provided by this module
  Description       = 'This DSC module is used to deploy and configure SharePoint Server 2013, 2016 and 2019, and covers a wide range of areas including web apps, service apps and farm configuration.'

  # Minimum version of the Windows PowerShell engine required by this module
  PowerShellVersion = '4.0'

  # Name of the Windows PowerShell host required by this module
  # PowerShellHostName = ''

  # Minimum version of the Windows PowerShell host required by this module
  # PowerShellHostVersion = ''

  # Minimum version of Microsoft .NET Framework required by this module
  # DotNetFrameworkVersion = ''

  # Minimum version of the common language runtime (CLR) required by this module
  # CLRVersion = ''

  # Processor architecture (None, X86, Amd64) required by this module
  # ProcessorArchitecture = ''

  # Modules that must be imported into the global environment prior to importing this module
  # RequiredModules = @()

  # Assemblies that must be loaded prior to importing this module
  # RequiredAssemblies = @()

  # Script files (.ps1) that are run in the caller's environment prior to importing this module.
  # ScriptsToProcess = @()

  # Type files (.ps1xml) to be loaded when importing this module
  # TypesToProcess = @()

  # Format files (.ps1xml) to be loaded when importing this module
  # FormatsToProcess = @()

  # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
  NestedModules     = @("modules\SharePointDsc.Util\SharePointDsc.Util.psm1")

  # Functions to export from this module
  #FunctionsToExport = '*'

  # Cmdlets to export from this module
  CmdletsToExport   = @("Invoke-SPDscCommand",
    "Get-SPDscInstalledProductVersion",
    "Get-SPDscContentService",
    "Rename-SPDscParamValue",
    "Add-SPDscUserToLocalAdmin",
    "Remove-SPDscUserToLocalAdmin",
    "Test-SPDscObjectHasProperty",
    "Test-SPDscRunAsCredential",
    "Test-SPDscUserIsLocalAdmin",
    "Test-SPDscParameterState",
    "Test-SPDscIsADUser",
    "Test-SPDscRunningAsFarmAccount",
    "Set-SPDscObjectPropertyIfValuePresent",
    "Get-SPDscUserProfileSubTypeManager",
    "Get-SPDscOSVersion",
    "Get-SPDscRegistryKey",
    "Resolve-SPDscSecurityIdentifier",
    "Get-SPDscFarmProductsInfo",
    "Get-SPDscFarmVersionInfo",
    "Convert-SPDscADGroupIDToName",
    "Convert-SPDscADGroupNameToID")

  # Variables to export from this module
  #VariablesToExport = '*'

  # Aliases to export from this module
  #AliasesToExport = '*'

  # List of all modules packaged with this module
  # ModuleList = @()

  # List of all files packaged with this module
  # FileList = @()

  # HelpInfo URI of this module
  # HelpInfoURI = ''

  # Default prefix for commands exported from this module. Override the default prefix using Import-Module -prefix.
  # DefaultCommandPrefix = ''

  # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
  PrivateData       = @{

    PSData = @{
      # Tags applied to this module. These help with module discovery in online galleries.
      Tags         = @('DesiredStateConfiguration', 'DSC', 'DSCResourceKit', 'DSCResource')

      # A URL to the license for this module.
      LicenseUri   = 'https://github.com/PowerShell/SharePointDsc/blob/master/LICENSE'

      # A URL to the main website for this project.
      ProjectUri   = 'https://github.com/PowerShell/SharePointDsc'

      # A URL to an icon representing this module.
      # IconUri = ''

      # ReleaseNotes of this module
      ReleaseNotes = "
          * SPConfigWizard
            * Fixed issue with incorrect check for upgrade status of server
          * SPDistributedCacheService
            * Improved error message for inclusion of server name into ServerProvisionOrder
              parameters when Present or change to Ensure Absent
          * SPFarm
            * Removed SingleServer as ServerRole, since this is an invalid role.
            * Handle case where null or empty CentralAdministrationUrl is passed in
            * Move CentralAdministrationPort validation into parameter definition
              to work with ReverseDsc
            * Add NotNullOrEmpty parameter validation to CentralAdministrationUrl
            * Fixed error when changing developer dashboard display level.
            * Add support for updating Central Admin Authentication Method
          * SPFarmSolution
            * Fix for Web Application scoped solutions.
          * SPInstall
            * Fixes a terminating error for sources in weird file shares
            * Corrected issue with incorrectly detecting SharePoint after it
              has been uninstalled
            * Corrected issue with detecting a paused installation
          * SPInstallLanguagePack
            * Fixes a terminating error for sources in weird file shares
          * SPInstallPrereqs
            * Fixes a terminating error for sources in weird file shares
          * SPProductUpdate
            * Fixes a terminating error for sources in weird file shares
            * Corrected incorrect farm detection, added in earlier bugfix
          * SPSite
            * Fixed issue with incorrectly updating site OwnerAlias and
              SecondaryOwnerAlias
          * SPWebAppAuthentication
            * Fixes issue where Test method return false on NON-US OS.
"
    } # End of PSData hashtable

  } # End of PrivateData hashtable
}

