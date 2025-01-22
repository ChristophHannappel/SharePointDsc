[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPSite'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DscResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Initialize tests
                try
                {
                    [Microsoft.SharePoint.Administration.SPAdministrationWebApplication]
                }
                catch
                {
                    Add-Type -TypeDefinition @"
        namespace Microsoft.SharePoint.Administration {
            public class SPAdministrationWebApplication {
                public SPAdministrationWebApplication()
                {
                }
                public static System.Object Local { get; set;}
            }
        }
"@
                }

                # Mocks for all contexts
                $siteImplementation =
                {
                    $rootWeb = @{
                        AssociatedVisitorGroup              = $null
                        AssociatedMemberGroup               = $null
                        AssociatedOwnerGroup                = $null
                        CreateDefaultAssociatedGroupsCalled = $false
                    }
                    $rootWeb | Add-Member -MemberType ScriptMethod `
                        -Name CreateDefaultAssociatedGroups `
                        -Value {
                        $this.CreateDefaultAssociatedGroupsCalled = $true
                    }
                    $rootWeb = $rootWeb | Add-Member -MemberType ScriptMethod `
                        -Name EnsureUser `
                        -Value { return "user" } -PassThru

                    $site = @{
                        HostHeaderIsSiteName   = $false
                        WebApplication         = @{
                            Url                     = "https://site.contoso.com"
                            UseClaimsAuthentication = $true
                        }
                        Url                    = "https://site.contoso.com"
                        Owner                  = @{ UserLogin = "DEMO\owner" }
                        Quota                  = @{ QuotaId = 65000 }
                        RootWeb                = $rootWeb
                        AdministrationSiteType = "None"
                    }
                    return $site
                }

                [Microsoft.SharePoint.Administration.SPAdministrationWebApplication]::Local = @{ Url = "https://CentralAdmin.contoso.com" }

                Mock -CommandName Get-SPSite -MockWith {
                    return @{
                        Id            = 1
                        SystemAccount = @{
                            UserToken = "CentralAdminSystemAccountUserToken"
                        }
                    }
                } -ParameterFilter {
                    $Identity -eq "https://CentralAdmin.contoso.com"
                }

                Mock -CommandName New-Object -MockWith {
                    $site = $siteImplementation.InvokeReturnAsIs()
                    $Script:SPDscSystemAccountSite = $site
                    return $site;
                } -ParameterFilter {
                    $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                    $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                }

                Mock -CommandName New-SPSite -MockWith {
                    $rootWeb = @{ }
                    $rootWeb = $rootWeb | Add-Member -MemberType ScriptMethod `
                        -Name CreateDefaultAssociatedGroups `
                        -Value { } -PassThru
                    $returnval = @{
                        HostHeaderIsSiteName = $true
                        WebApplication       = @{
                            Url                     = $testParams.Url
                            UseClaimsAuthentication = $false
                        }
                        Url                  = $testParams.Url
                        Owner                = @{ UserLogin = "DEMO\owner" }
                        SecondaryContact     = @{ UserLogin = "DEMO\secondowner" }
                        Quota                = @{
                            QuotaId = 1
                        }
                        RootWeb              = $rootWeb
                    }
                    return $returnval
                }
                Mock -CommandName Get-SPDscContentService -MockWith {
                    $quotaTemplates = @(@{
                            Test = @{
                                QuotaId = 65000
                            }
                        })
                    $quotaTemplatesCol = { $quotaTemplates }.Invoke()

                    $contentService = @{
                        QuotaTemplates = $quotaTemplatesCol
                    }

                    $contentService = $contentService | Add-Member -MemberType ScriptMethod `
                        -Name Update `
                        -Value {
                        $Global:SPDscQuotaTemplatesUpdated = $true
                    } -PassThru
                    return $contentService
                }
            }

            # Test contexts
            Context -Name "The site doesn't exist yet and should" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url        = "http://site.sharepoint.com"
                        OwnerAlias = "DEMO\User"
                    }

                    Mock -CommandName New-Object -MockWith {
                        return $null;
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq "http://site.sharepoint.com" -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    # Mock Get-SPSite for SPSSE on Get-TargetResource Call
                    if ($Global:SPDscHelper.CurrentStubBuildNumber.Build -gt 13000)
                    {
                        $global:SPDscGetSPSiteCalledCount = 0
                        Mock -CommandName Get-SPSite -MockWith {
                            if ($global:SPDscGetSPSiteCalledCount -lt 4)
                            {
                                ++$global:SPDscGetSPSiteCalledCount
                                return $null
                            }
                            else
                            {
                                return ""
                            }
                        } -ParameterFilter {
                            $Identity -eq "http://site.sharepoint.com"
                        }
                    }
                    else
                    {
                        $global:SPDscGetSPSiteCalled = $false
                        Mock -CommandName Get-SPSite -MockWith {
                            if ($global:SPDscGetSPSiteCalled)
                            {
                                return ""
                            }
                            else
                            {
                                $global:SPDscGetSPSiteCalled = $true
                                return $null
                            }
                        }
                    }



                    Mock -CommandName Start-Process -MockWith {
                        return @{
                            ExitCode = 0
                        }
                    }
                }

                It "Should return OwnerAlias=Null from the get method" {
                    (Get-TargetResource @testParams).OwnerAlias | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should create a new site from the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Start-Process
                }
            }

            Context -Name "The site exists, but has incorrect owner alias and quota" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url                    = "http://site.sharepoint.com"
                        OwnerAlias             = "DEMO\User"
                        SecondaryOwnerAlias    = "DEMO\SecondUser"
                        QuotaTemplate          = "Test"
                        AdministrationSiteType = "TenantAdministration"
                    }

                    $contextSiteImplementation = {
                        $site = $siteImplementation.InvokeReturnAsIs()
                        $site.WebApplication.Url = $testParams.Url
                        $site.WebApplication.UseClaimsAuthentication = $false
                        $site.Url = $testParams.Url
                        $site.Owner = @{ UserLogin = "DEMO\owner" }
                        $site.SecondaryContact = @{ UserLogin = "DEMO\secondowner" }
                        $site.Quota = @{
                            QuotaId = 1
                        }
                        return $site;
                    }

                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSite = $site
                        return $site
                    }

                    Mock -CommandName Set-SPSite -MockWith { } -ParameterFilter {
                        $QuotaTemplate = "Test"
                        $AdministrationSiteType -eq "TenantAdministration"
                    }
                    Mock -CommandName Get-SPDscContentService -MockWith {
                        $quotaTemplates = @(@{
                                QuotaId       = 1
                                Name          = "WrongTemplate"
                                WrongTemplate = @{
                                    StorageMaximumLevel  = 512
                                    StorageWarningLevel  = 256
                                    UserCodeMaximumLevel = 400
                                    UserCodeWarningLevel = 200
                                }
                            })
                        $quotaTemplatesCol = { $quotaTemplates }.Invoke()

                        $contentService = @{
                            QuotaTemplates = $quotaTemplatesCol
                        }
                        return $contentService
                    }
                }

                It "Should return the site data from the get method" {
                    $result = Get-TargetResource @testParams
                    $result.OwnerAlias | Should -Be "DEMO\owner"
                    $result.SecondaryOwnerAlias | Should -Be "DEMO\SecondOwner"
                    $result.QuotaTemplate | Should -Be "WrongTemplate"
                    $result.AdministrationSiteType | Should -Be "None"
                }

                It "Should update owner and quota in the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Set-SPSite
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }
            }

            Context -Name "The site exists and is a host named site collection" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url        = "http://site.sharepoint.com"
                        OwnerAlias = "DEMO\owner"
                    }

                    $contextSiteImplementation = {
                        $site = $siteImplementation.InvokeReturnAsIs()
                        $site.RootWeb.AssociatedVisitorGroup = "Test Visitors"
                        $site.RootWeb.AssociatedMemberGroup = "Test Members"
                        $site.RootWeb.AssociatedOwnerGroup = "Test Owners"

                        $site.WebApplication.Url = $testParams.Url
                        $site.WebApplication.UseClaimsAuthentication = $false
                        $site.HostHeaderIsSiteName = $true
                        $site.Url = $testParams.Url
                        $site.Owner = @{ UserLogin = "DEMO\owner" }
                        return $site;
                    }

                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSite = $site
                        return $site
                    }
                }

                It "Should return the site data from the get method" {
                    (Get-TargetResource @testParams).OwnerAlias | Should -Be "DEMO\owner"
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The site exists, but doesn't have default groups configured" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url                 = "http://site.sharepoint.com"
                        OwnerAlias          = "DEMO\User"
                        CreateDefaultGroups = $true
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        $site = $siteImplementation.InvokeReturnAsIs()
                        $site.RootWeb.AssociatedVisitorGroup = $null
                        $site.RootWeb.AssociatedMemberGroup = $null
                        $site.RootWeb.AssociatedOwnerGroup = $null

                        $site.WebApplication.Url = $testParams.Url
                        $site.Url = $testParams.Url
                        return $site
                    }

                    Mock -CommandName New-SPClaimsPrincipal -MockWith {
                        return @{
                            Value = $testParams.OwnerAlias
                        }
                    }
                }

                It "Should return CreateDefaultGroups=False from the get method" {
                    (Get-TargetResource @testParams).CreateDefaultGroups | Should -Be $false
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update the groups in the set method" {
                    Set-TargetResource @testParams
                    $Script:SPDscSystemAccountSite.RootWeb.CreateDefaultAssociatedGroupsCalled | Should -Be $true
                }
            }

            Context -Name "The site exists and uses claims authentication" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url        = "http://site.sharepoint.com"
                        OwnerAlias = "DEMO\User"
                    }

                    $contextSiteImplementation = {
                        $site = $siteImplementation.InvokeReturnAsIs()
                        $site.RootWeb.AssociatedVisitorGroup = "Test Visitors"
                        $site.RootWeb.AssociatedMemberGroup = "Test Members"
                        $site.RootWeb.AssociatedOwnerGroup = "Test Owners"

                        $site.WebApplication.Url = $testParams.Url
                        $site.WebApplication.UseClaimsAuthentication = $true
                        $site.HostHeaderIsSiteName = $false
                        $site.Url = $testParams.Url
                        $site.Owner = @{ UserLogin = "DEMO\owner" }
                        $site.Quota = @{ QuotaId = 65000 }
                        return $site;
                    }

                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSite = $site
                        return $site
                    }

                    Mock -CommandName New-SPClaimsPrincipal -MockWith {
                        return @{
                            Value = $testParams.OwnerAlias
                        }
                    }
                }

                It "Should return the site data from the get method" {
                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }

                It "Should return the site data from the get method where a valid site collection admin does not exist" {
                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $site.Owner = $null
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return the site data from the get method where a secondary site contact exists" {
                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $site.Owner = @{ UserLogin = "DEMO\owner" }
                        $site.SecondaryContact = @{ UserLogin = "DEMO\secondary" }
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return the site data from the get method where the site owner is in classic format" {
                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $site.Owner = @{ UserLogin = "DEMO\owner" }
                        $site.SecondaryContact = @{ UserLogin = "DEMO\secondary" }
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Mock -CommandName New-SPClaimsPrincipal -MockWith {
                        return $null
                    }

                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }
            }

            Context -Name "The site exists and uses classic authentication" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url        = "http://site.sharepoint.com"
                        OwnerAlias = "DEMO\owner"
                    }

                    $contextSiteImplementation = {
                        $site = $siteImplementation.InvokeReturnAsIs()
                        $site.RootWeb.AssociatedVisitorGroup = "Test Visitors"
                        $site.RootWeb.AssociatedMemberGroup = "Test Members"
                        $site.RootWeb.AssociatedOwnerGroup = "Test Owners"

                        $site.WebApplication.Url = $testParams.Url
                        $site.WebApplication.UseClaimsAuthentication = $false
                        $site.HostHeaderIsSiteName = $false
                        $site.Url = $testParams.Url
                        $site.Owner = @{ UserLogin = "DEMO\owner" }
                        $site.Quota = @{ QuotaId = 65000 }
                        return $site;
                    }

                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSite = $site
                        return $site
                    }
                }

                It "Should return the site data from the get method" {
                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }

                It "Should return the site data from the get method where a secondary site contact exists" {
                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $false
                            WebApplication       = @{
                                Url                     = $testParams.Url
                                UseClaimsAuthentication = $false
                            }
                            Url                  = $testParams.Url
                            Owner                = @{ UserLogin = "DEMO\owner" }
                            SecondaryContact     = @{ UserLogin = "DEMO\secondary" }
                            Quota                = @{ QuotaId = 65000 }
                        }
                    }

                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }
            }

            Context -Name "CreateDefaultGroups is set to false, don't correct anything" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url                 = "http://site.sharepoint.com"
                        OwnerAlias          = "DEMO\owner"
                        CreateDefaultGroups = $false
                    }

                    $contextSiteImplementation = {
                        $site = $siteImplementation.InvokeReturnAsIs()
                        $site.RootWeb.AssociatedVisitorGroup = $null
                        $site.RootWeb.AssociatedMemberGroup = $null
                        $site.RootWeb.AssociatedOwnerGroup = $null

                        $site.WebApplication.Url = $testParams.Url
                        $site.WebApplication.UseClaimsAuthentication = $false
                        $site.HostHeaderIsSiteName = $false
                        $site.Url = $testParams.Url
                        $site.Owner = @{ UserLogin = "DEMO\owner" }
                        $site.Quota = @{ QuotaId = 65000 }
                        return $site;
                    }

                    Mock -CommandName New-Object -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSystemAccountSite = $site
                        return $site
                    } -ParameterFilter {
                        $TypeName -eq "Microsoft.SharePoint.SPSite" -and
                        $ArgumentList[0] -eq $testParams.Url -and
                        $ArgumentList[1] -eq "CentralAdminSystemAccountUserToken"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        $site = $contextSiteImplementation.InvokeReturnAsIs()
                        $Script:SPDscSite = $site
                        return $site
                    }
                }

                It "Should return CreateDefaultGroups=False from the get method" {
                    (Get-TargetResource @testParams).CreateDefaultGroups | Should -Be $false
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "Running ReverseDsc Export" -Fixture {
                BeforeAll {
                    Import-Module (Join-Path -Path (Split-Path -Path (Get-Module SharePointDsc -ListAvailable).Path -Parent) -ChildPath "Modules\SharePointDSC.Reverse\SharePointDSC.Reverse.psm1")

                    Mock -CommandName Write-Host -MockWith { }

                    Mock -CommandName Get-TargetResource -MockWith {
                        return @{
                            Url                      = "http://sharepoint.contoso.com"
                            OwnerAlias               = "CONTOSO\ExampleUser"
                            OwnerEmail               = "user@contoso.com"
                            HostHeaderWebApplication = "http://spsites.contoso.com"
                            Name                     = "Team Sites"
                            Template                 = "STS#0"
                            QuotaTemplate            = "Teamsite"
                            CompatibilityLevel       = 15
                            ContentDatabase          = "ContentDB"
                            Description              = "Demo Site Col"
                            Language                 = 1033
                            SecondaryEmail           = "user2@contoso.com"
                            SecondaryOwnerAlias      = "CONTOSO\ExampleUser2"
                            CreateDefaultGroups      = $true
                        }
                    }

                    Mock -CommandName Get-SPDscContentService -MockWith {
                        return @{
                            QuotaTemplates = @(
                                @{
                                    QuotaId = 1
                                }
                            )
                        }
                    }
                    Mock -CommandName Get-SPSite -MockWith {
                        $spSites = @(
                            @{
                                IsSiteMaster   = $false
                                RootWeb        = @{
                                    Title = "Team Sites"
                                }
                                Url            = "http://sharepoint.contoso.com"
                                WebApplication = @{
                                    Name = "SharePoint Content WebApplication"
                                }
                                Quota          = @{
                                    QuotaID = 1
                                }
                            }
                        )
                        return $spSites
                    }

                    Mock -CommandName Read-TargetResource -MockWith {}

                    if ($null -eq (Get-Variable -Name 'spFarmAccount' -ErrorAction SilentlyContinue))
                    {
                        $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                        $Global:spFarmAccount = New-Object -TypeName System.Management.Automation.PSCredential ("contoso\spfarm", $mockPassword)
                    }

                    if ($null -eq (Get-Variable -Name 'ExtractionModeValue' -ErrorAction SilentlyContinue))
                    {
                        $Global:ExtractionModeValue = 1
                    }

                    if ($null -eq (Get-Variable -Name 'ComponentsToExtract' -ErrorAction SilentlyContinue))
                    {
                        $Global:ComponentsToExtract = @()
                    }

                    $result = @'
        SPSite [0-9A-Fa-f]{8}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{12}
        {
            CompatibilityLevel       = 15;
            ContentDatabase          = "ContentDB";
            CreateDefaultGroups      = \$True;
            Description              = "Demo Site Col";
            HostHeaderWebApplication = "http://spsites.contoso.com";
            Language                 = 1033;
            Name                     = "Team Sites";
            OwnerAlias               = "CONTOSO\\ExampleUser";
            OwnerEmail               = "user\@contoso.com";
            PsDscRunAsCredential     = \$Credsspfarm;
            SecondaryEmail           = "user2\@contoso.com";
            SecondaryOwnerAlias      = "CONTOSO\\ExampleUser2";
            Template                 = "STS\#0";
            Url                      = "http://sharepoint.contoso.com";
            DependsOn =  \@\("\[SPWebApplication\]SharePointContentWebApplication"\);
        }

'@
                }

                It "Should return valid DSC block from the Export method" {
                    Export-TargetResource | Should -Match $result
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
