# Ignoring this because we need to generate a stub credential to run the tests here
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
[CmdletBinding()]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

#region HEADER
$script:projectPath = "$PSScriptRoot\..\..\.." | Convert-Path
$script:projectName = (Get-ChildItem -Path "$script:projectPath\*\*.psd1" | Where-Object -FilterScript {
        ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) -and
        $(try
            {
                Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
            }
            catch
            {
                $false
            })
    }).BaseName

$script:parentModule = Get-Module -Name $script:projectName -ListAvailable | Select-Object -First 1
$script:subModulesFolder = Join-Path -Path $script:parentModule.ModuleBase -ChildPath 'Modules'
Remove-Module -Name $script:parentModule -Force -ErrorAction 'SilentlyContinue'

$script:subModuleName = (Split-Path -Path $PSCommandPath -Leaf) -replace '\.Tests.ps1'
$script:subModuleFile = Join-Path -Path $script:subModulesFolder -ChildPath "$($script:subModuleName)"

Import-Module $script:subModuleFile -Force -ErrorAction Stop
#endregion HEADER

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $moduleVersionFolder = ($ModuleVersion -split "-")[0]

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -SubModulePath "Modules\SharePointDsc.Util\SharePointDsc.Util.psm1" `
            -ExcludeInvokeHelper `
            -ModuleVersion $moduleVersionFolder
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }
}

function Invoke-TestCleanup
{
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $Global:SPDscHelper.ModuleName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -Scriptblock $Global:SPDscHelper.InitializeScript -NoNewScope

                Mock -CommandName Add-SPDscEvent -MockWith {}
            }

            Context -Name "Validate Get-SPDscAssemblyVersion" -Fixture {
                It "Should return the version number of a given executable" {
                    $testPath = "C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe"
                    Get-SPDscAssemblyVersion -PathToAssembly $testPath | Should -Not -Be 0
                }
            }

            Context -Name "Validate Invoke-SPDscCommand" -Fixture {
                BeforeAll {
                    Mock -CommandName Invoke-Command -MockWith {
                        return $null
                    }
                    Mock -CommandName New-PSSession -MockWith {
                        return $null
                    }
                    Mock -CommandName Get-PSSnapin -MockWith {
                        return $null
                    }
                    Mock -CommandName Add-PSSnapin -MockWith {
                        return $null
                    }
                }

                # The use of the '4>&1' operator is used to hide the verbose output from the
                # Invoke-SPDscCommand command in these tests as it is not necessary to Validate
                # the output of the tests.

                It "Should execute a command as the local run as user" {
                    Invoke-SPDscCommand -ScriptBlock { return "value" } 4>&1
                }

                It "Should execute a command as the local run as user with additional arguments" {
                    Invoke-SPDscCommand -ScriptBlock { return "value" } `
                        -Arguments @{ Something = "42" } 4>&1
                }

                It "Should execute a command as the specified InstallAccount user where it is different to the current user" {
                    $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                    $mockCredential = New-Object -TypeName System.Management.Automation.PSCredential ("username", $mockPassword)
                    Invoke-SPDscCommand -ScriptBlock { return "value" } `
                        -Credential $mockCredential 4>&1
                }

                It "Should throw an exception when the run as user is the same as the InstallAccount user" {
                    $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                    $mockCredential = New-Object -TypeName System.Management.Automation.PSCredential ("$($Env:USERDOMAIN)\$($Env:USERNAME)", $mockPassword)
                    { Invoke-SPDscCommand -ScriptBlock { return "value" } `
                            -Credential $mockCredential 4>&1 } | Should -Throw
                }

                It "Should throw normal exceptions when triggered in the script block" {
                    Mock -CommandName Invoke-Command -MockWith {
                        throw [Exception] "A random exception"
                    }

                    { Invoke-SPDscCommand -ScriptBlock { return "value" } 4>&1 } | Should -Throw
                }

                It "Should throw normal exceptions when triggered in the script block using InstallAccount" {
                    Mock -CommandName Invoke-Command -MockWith {
                        throw [Exception] "A random exception"
                    }

                    $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                    $mockCredential = New-Object -TypeName System.Management.Automation.PSCredential ("username", $mockPassword)
                    { Invoke-SPDscCommand -ScriptBlock { return "value" } `
                            -Credential $mockCredential 4>&1 } | Should -Throw
                }

                It "Should handle a SharePoint update conflict exception by rebooting the server to retry" {
                    Mock -CommandName Invoke-Command -MockWith {
                        throw [Exception] "An update conflict has occurred, and you must re-try this action."
                    }

                    { Invoke-SPDscCommand -ScriptBlock { return "value" } 4>&1 } | Should -Not -Throw
                }

                It "Should handle a SharePoint update conflict exception by rebooting the server to retry using InstallAccount" {
                    Mock -CommandName Invoke-Command -MockWith {
                        throw [Exception] "An update conflict has occurred, and you must re-try this action."
                    }

                    $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                    $mockCredential = New-Object -TypeName System.Management.Automation.PSCredential ("username", $mockPassword)
                    { Invoke-SPDscCommand -ScriptBlock { return "value" } `
                            -Credential $mockCredential 4>&1 } | Should -Not -Throw
                }
            }

            Context -Name "Validate Test-SPDscParameterState" -Fixture {
                It "Should return true for two identical tables" {
                    $desired = @{ Example = "test" }
                    Test-SPDscParameterState -CurrentValues $desired `
                        -Source 'SharePointDsc.Util' `
                        -DesiredValues $desired | Should -Be $true
                }

                It "Should return false when a value is different" {
                    $current = @{ Example = "something" }
                    $desired = @{ Example = "test" }
                    Test-SPDscParameterState -CurrentValues $current `
                        -Source 'SharePointDsc.Util' `
                        -DesiredValues $desired | Should -Be $false
                }

                It "Should return false when a value is missing" {
                    $current = @{ }
                    $desired = @{ Example = "test" }
                    Test-SPDscParameterState -CurrentValues $current `
                        -Source 'SharePointDsc.Util' `
                        -DesiredValues $desired | Should -Be $false
                }

                It "Should return true when only a specified value matches, but other non-listed values do not" {
                    $current = @{ Example = "test"; SecondExample = "true" }
                    $desired = @{ Example = "test"; SecondExample = "false" }
                    Test-SPDscParameterState -CurrentValues $current `
                        -Source 'SharePointDsc.Util' `
                        -DesiredValues $desired `
                        -ValuesToCheck @("Example") | Should -Be $true
                }

                It "Should return false when only specified values do not match, but other non-listed values do " {
                    $current = @{ Example = "test"; SecondExample = "true" }
                    $desired = @{ Example = "test"; SecondExample = "false" }
                    Test-SPDscParameterState -CurrentValues $current `
                        -Source 'SharePointDsc.Util' `
                        -DesiredValues $desired `
                        -ValuesToCheck @("SecondExample") | Should -Be $false
                }

                It "Should return false when an empty array is used in the current values" {
                    $current = @{ }
                    $desired = @{ Example = "test"; SecondExample = "false" }
                    Test-SPDscParameterState -CurrentValues $current `
                        -Source 'SharePointDsc.Util' `
                        -DesiredValues $desired | Should -Be $false
                }
            }

            Context -Name "Validate Convert-SPDscADGroupIDToName" -Fixture {
                BeforeAll {
                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.DirectoryServices.DirectoryEntry"
                    } -MockWith { return @{
                            objectGUID = @{
                                Value = (New-Guid)
                            }
                        } }

                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.DirectoryServices.DirectorySearcher"
                    } -MockWith {
                        $searcher = @{
                            SearchRoot       = $null
                            PageSize         = $null
                            Filter           = $null
                            SearchScope      = $null
                            PropertiesToLoad = (New-Object -TypeName "System.Collections.Generic.List[System.String]")
                        }
                        $searcher = $searcher | Add-Member -MemberType ScriptMethod `
                            -Name FindOne `
                            -Value {
                            $result = @{ }
                            $result = $result | Add-Member -MemberType ScriptMethod `
                                -Name GetDirectoryEntry `
                                -Value {
                                return @{
                                    objectsid = @("item")
                                }
                            } -PassThru -Force
                            return $result
                        } -PassThru -Force
                        return $searcher
                    }

                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.Security.Principal.SecurityIdentifier"
                    } -MockWith {
                        $sid = @{ }
                        $sid = $sid | Add-Member -MemberType ScriptMethod `
                            -Name Translate `
                            -Value {
                            $returnVal = $global:SPDscGroupsToReturn[$global:SPDscSidCount]
                            $global:SPDscSidCount++
                            return $returnVal
                        } -PassThru -Force
                        return $sid
                    }

                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.Security.Principal.NTAccount"
                    } -MockWith {
                        $sid = @{ }
                        $sid = $sid | Add-Member -MemberType ScriptMethod `
                            -Name Translate `
                            -Value {
                            $returnVal = $global:SPDscSidsToReturn[$global:SPDscSidCount]
                            $global:SPDscSidCount++
                            return $returnVal
                        } -PassThru -Force
                        return $sid
                    }
                }

                It "should convert an ID to an AD domain name" {
                    $global:SPDscGroupsToReturn = @("DOMAIN\Group 1")
                    $global:SPDscSidsToReturn = @("example SID")
                    $global:SPDscSidCount = 0
                    Convert-SPDscADGroupIDToName -GroupId (New-Guid) | Should -Be "DOMAIN\Group 1"
                }

                It "should throw an error if no result is found in AD" {
                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.DirectoryServices.DirectorySearcher"
                    } -MockWith {
                        $searcher = @{
                            SearchRoot       = $null
                            PageSize         = $null
                            Filter           = $null
                            SearchScope      = $null
                            PropertiesToLoad = (New-Object -TypeName "System.Collections.Generic.List[System.String]")
                        }
                        $searcher = $searcher | Add-Member -MemberType ScriptMethod `
                            -Name FindOne `
                            -Value {
                            return $null
                        } -PassThru -Force
                        return $searcher
                    }

                    $global:SPDscGroupsToReturn = @("DOMAIN\Group 1")
                    $global:SPDscSidsToReturn = @("example SID")
                    $global:SPDscSidCount = 0
                    { Convert-SPDscADGroupIDToName -GroupId (New-Guid) } | Should -Throw
                }
            }

            Context -Name "Validate Convert-SPDscADGroupNameToId" -Fixture {
                BeforeAll {
                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.DirectoryServices.DirectoryEntry"
                    } -MockWith { return @{
                            objectGUID = @{
                                Value = (New-Guid)
                            }
                        } }

                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.DirectoryServices.DirectorySearcher"
                    } -MockWith {
                        $searcher = @{
                            SearchRoot       = $null
                            PageSize         = $null
                            Filter           = $null
                            SearchScope      = $null
                            PropertiesToLoad = (New-Object -TypeName "System.Collections.Generic.List[System.String]")
                        }
                        $searcher = $searcher | Add-Member -MemberType ScriptMethod `
                            -Name FindOne `
                            -Value {
                            $result = @{ }
                            $result = $result | Add-Member -MemberType ScriptMethod `
                                -Name GetDirectoryEntry `
                                -Value {
                                return @{
                                    objectsid = @("item")
                                }
                            } -PassThru -Force
                            return $result
                        } -PassThru -Force
                        return $searcher
                    }

                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.Security.Principal.SecurityIdentifier"
                    } -MockWith {
                        $sid = @{ }
                        $sid = $sid | Add-Member -MemberType ScriptMethod `
                            -Name Translate `
                            -Value {
                            $returnVal = $global:SPDscGroupsToReturn[$global:SPDscSidCount]
                            $global:SPDscSidCount++
                            return $returnVal
                        } -PassThru -Force
                        return $sid
                    }

                    Mock -CommandName "New-Object" -ParameterFilter {
                        $TypeName -eq "System.Security.Principal.NTAccount"
                    } -MockWith {
                        $sid = @{ }
                        $sid = $sid | Add-Member -MemberType ScriptMethod `
                            -Name Translate `
                            -Value {
                            $returnVal = $global:SPDscSidsToReturn[$global:SPDscSidCount]
                            $global:SPDscSidCount++
                            return $returnVal
                        } -PassThru -Force
                        return $sid
                    }
                }

                It "should convert an AD domain name to an ID" {
                    $global:SPDscGroupsToReturn = @("DOMAIN\Group 1")
                    $global:SPDscSidsToReturn = @("example SID")
                    $global:SPDscSidCount = 0
                    Convert-SPDscADGroupIDToName -GroupId (New-Guid) | Should -Not -BeNullOrEmpty
                }
            }

            Context -Name "Validate Get-SPDscServerPatchStatus" -Fixture {
                BeforeAll {
                    try
                    {
                        [Microsoft.SharePoint.Administration.SPProductVersions]
                    }
                    catch
                    {
                        Add-Type -TypeDefinition @"
                        namespace Microsoft.SharePoint.Administration {
                            public class serverProductInfo {
                                public string GetUpgradeStatus(System.Object farm, System.Object server)
                                {
                                    return "NoActionRequired";
                                }

                                public string InstallStatus
                                {
                                    get
                                    {
                                        return "NoActionRequired";
                                    }
                                }
                            }
                            public class ProductVersions {
                                public object GetServerProductInfo(System.Object server)
                                {
                                    return new serverProductInfo();
                                }
                            }
                            public class SPProductVersions {
                                public static object GetProductVersions(System.Object obj)
                                {
                                    return new ProductVersions();
                                }
                            }
                        }
"@ -ErrorAction SilentlyContinue
                    }

                    Mock -CommandName Get-SPFarm -MockWith { return "" }
                    Mock -CommandName Get-SPServer -MockWith {
                        return @{
                            Id = (New-Guid)
                        }
                    }
                }

                It "should return the patch status of the current server" {
                    Get-SPDscServerPatchStatus | Should -Be "NoActionRequired"
                }
            }

            Context -Name "Validate Get-SPDscAllServersPatchStatus" -Fixture {
                BeforeAll {
                    try
                    {
                        [Microsoft.SharePoint.Administration.SPProductVersions]
                    }
                    catch
                    {
                        Add-Type -TypeDefinition @"
                        namespace Microsoft.SharePoint.Administration {
                            public class serverProductInfo {
                                public string GetUpgradeStatus(System.Object farm, System.Object server)
                                {
                                    return "NoActionRequired";
                                }

                                public string InstallStatus
                                {
                                    get
                                    {
                                        return "NoActionRequired";
                                    }
                                }
                            }
                            public class ProductVersions {
                                public object GetServerProductInfo(System.Object server)
                                {
                                    return new serverProductInfo();
                                }
                            }
                            public class SPProductVersions {
                                public static object GetProductVersions(System.Object obj)
                                {
                                    return new ProductVersions();
                                }
                            }
                        }
"@ -ErrorAction SilentlyContinue
                    }

                    Mock -CommandName Get-SPFarm -MockWith { return "" }
                    Mock -CommandName Get-SPServer -MockWith {
                        return @{
                            Name = "WFE01"
                            Id   = (New-Guid)
                            Role = "WebFrontEnd"
                        }
                    }
                }

                It "should return the patch status of the current server" {
                    [array]$result = Get-SPDscAllServersPatchStatus
                    $result.Count | Should -Be 1
                    $result[0].Name | Should -Be "WFE01"
                }
            }


            Context -Name "Validate Export-SPDscDiagnosticData" -Fixture {
                BeforeAll {
                    Mock -CommandName "New-Object" `
                        -ParameterFilter {
                        $TypeName -eq "Security.Principal.WindowsPrincipal"
                    } -MockWith {
                        $returnval = "Test"
                        $returnval = $returnval | Add-Member -MemberType ScriptMethod `
                            -Name IsInRole `
                            -Value {
                            return $true
                        } -PassThru -Force

                        return $returnval
                    }

                    Mock -CommandName Write-Host -MockWith {}

                    Mock -CommandName Copy-Item -MockWith {
                        Set-Content -Path (Join-Path -Path $Destination -ChildPath "test.json") -Value @"
URL = http://sharepoint.contoso.com"
Server = SERVER1
"@
                    }

                    Mock -CommandName Get-EventLog -MockWith {
                        $returnval = @()
                        $returnval += [pscustomobject]@{
                            Index          = 10202
                            EntryType      = 'Error'
                            InstanceId     = 1
                            Message        = 'Message'
                            Category       = '(1)'
                            CategoryNumber = 1
                            MachineName    = 'SERVER1'
                            Source         = 'MSFT_SPWorkManagementServiceApp'
                            TimeGenerated  = Get-Date
                            TimeWritten    = Get-Date
                            UserName       = ""
                        }
                        $returnval += [pscustomobject]@{
                            Index          = 10201
                            EntryType      = 'Warning'
                            InstanceId     = 1
                            Message        = 'Message'
                            Category       = '(1)'
                            CategoryNumber = 1
                            MachineName    = 'SERVER1'
                            Source         = 'MSFT_SPWorkManagementServiceApp'
                            TimeGenerated  = Get-Date
                            TimeWritten    = Get-Date
                            UserName       = ""
                        }
                        return $returnval
                    }

                    Mock -CommandName Get-ComputerInfo -MockWith {
                        return @"
            OsName               : Microsoft Windows 10 Enterprise
            OsOperatingSystemSKU : EnterpriseEdition
            OsArchitecture       : 64-bit
            WindowsVersion       : 2009
            WindowsBuildLabEx    : 19041.1.amd64fre.vb_release.191206-1406
            OsLanguage           : en-US
            OsMuiLanguages       : {en-US, en-GB, nl-NL}
"@
                    }

                    Mock -CommandName Get-DscLocalConfigurationManager -MockWith {
                        return @"
ActionAfterReboot              : ContinueConfiguration
AgentId                        : 43C51C89-F9FA-11EA-94E5-2816A80571C0
AllowModuleOverWrite           : False
CertificateID                  :
ConfigurationDownloadManagers  : {}
ConfigurationID                :
ConfigurationMode              : ApplyAndMonitor
ConfigurationModeFrequencyMins : 15
Credential                     :
DebugMode                      : {}
DownloadManagerCustomData      :
DownloadManagerName            :
LCMCompatibleVersions          : {1.0, 2.0}
LCMState                       : Idle
LCMStateDetail                 :
LCMVersion                     : 2.0
StatusRetentionTimeInDays      : 10
SignatureValidationPolicy      : NONE
SignatureValidations           : {}
MaximumDownloadSizeMB          : 500
PartialConfigurations          :
RebootNodeIfNeeded             : False
RefreshFrequencyMins           : 30
RefreshMode                    : PUSH
ReportManagers                 : {}
ResourceModuleManagers         : {}
PSComputerName                 :
"@
                    }

                    Mock -CommandName Compress-Archive -MockWith {}
                }

                It "should export and anonymize diagnostic data" {
                    Export-SPDscDiagnosticData -ExportFilePath 'C:\Temp\SPDsc.zip' -Anonymize -Server 'SERVER1' -Domain 'CONTOSO' -URL 'contoso.com'
                    Assert-MockCalled -CommandName Get-EventLog -Times 1
                    Assert-MockCalled -CommandName Get-ComputerInfo -Times 1
                    Assert-MockCalled -CommandName Get-DscLocalConfigurationManager -Times 1
                    Assert-MockCalled -CommandName Compress-Archive -Times 1
                }
            }
        }
    }
}
finally
{
}
