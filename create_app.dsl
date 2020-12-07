/*

Example of Application:

Electric Flow DSL - Create a deployable application
This example creates bare bones application model, artifacts and environment model that can be run to install a dummy application.  It exercises and illustrates the following key Electric Flow features:

- Application Modeling
	- Components that reference an artifact management system (Electric Flow Artifact Management)
	- Multiple tiers to target different content types to different server groups
	- Manual approval step
	- Rollback (on manual rejection)
- Artifact Management
	- Adding files programmatically through a procedure
- Environment Modeling
	- Multiple tiers to group different servers (all resources are mapped to 'localhost' for this example)

Instructions
1. Run this code through the DSLIDE (optionally edit the Customizable values below)
2. Navigate to the application model
3. Run the Deploy process to an environment in this project
4. Select Success in the Manual approval
5. Examine the Environment Inventory for this project
6. Run again with Smart Deploy turned off
7. Fail the Manual Validate step, this will cause roll back

Limitations
- Only works with Linux Electric Flow host

*/


// Customizable values ------------------

// Application Name
def ProjectName = "snaqvi Demo"
def AppName = "DSLIDE Application"
def Envs = ["QA","UAT"]

// Application-Environment tier mapping ["apptier1":"envtier1", "apptier2":"envtier2" ...]
// The values will be used to create application and environment tier names and their mappings
def AppEnvTiers = ["App":"Tomcat", "DB":"MySQL"]

// Artifact group id
def ArtifactRoot = "com.mycompany.dslide"


// Clean up from prior runs ------------------

def EnvTiers = AppEnvTiers.values()
def AppTiers = AppEnvTiers.keySet()

// Remove old application model
deleteApplication (projectName: ProjectName, applicationName: AppName)

// Remove old Environment models
Envs.each { Env ->
    AppTiers.each() { Tier ->
        def res = "${Env}_${Tier}"
        deleteResource resourceName: res
    }
    deleteEnvironment(projectName: ProjectName, environmentName: Env)
}

// Create new -------------------------------

def ArtifactVersions = []

project ProjectName, {

    // Create Environments, Tiers and Resources
    Envs.each { Env ->
        environment environmentName: Env, {
            EnvTiers.each() { Tier ->
                def res = "${Env}_${Tier}"
                environmentTier Tier, {
                    // create and add resource to the Tier
                    resource resourceName: res, hostName : "1.1.1.1"
                }
            }
        }
    } // Environments

    application AppName, {

        AppTiers.each() { Tier ->
            applicationTier Tier, {
                def CompName = "${Tier}_comp"
                def ArtifactVersion = "1.35"
                def ArtifactName = ArtifactRoot + ':' + CompName
                ArtifactVersions << [artifactName: ArtifactName, artifactVersion: ArtifactVersion]
                // Create artifact
                artifact groupId: ArtifactRoot, artifactKey: CompName

                component CompName, pluginKey: "EC-Artifact", {
                    ec_content_details.with {
                        pluginProjectName = "EC-Artifact"
                        pluginProcedure = "Retrieve"
                        artifactName = ArtifactName
                        filterList = ""
                        overwrite = "update"
                        versionRange = ArtifactVersion
                        artifactVersionLocationProperty = "/myJob/retrievedArtifactVersions/\$" + "[assignedResourceName]"
                    }

                    process "Install", processType: "DEPLOY", componentApplicationName: AppName,{
                        processStep "Retrieve Artifact",
                                processStepType: "component",
                                subprocedure: "Retrieve",
                                errorHandling: "failProcedure",
                                subproject: "/plugins/EC-Artifact/project",
                                applicationName: null,
                                applicationTierName: null,
                                actualParameter: [
                                        artifactName : "\$" + "[/myComponent/ec_content_details/artifactName]",
                                        artifactVersionLocationProperty : "\$" + "[/myComponent/ec_content_details/artifactVersionLocationProperty]",
                                        filterList : "\$" + "[/myComponent/ec_content_details/filterList]",
                                        overwrite : "\$" + "[/myComponent/ec_content_details/overwrite]",
                                        versionRange : "\$" + "[/myJob/ec_" + CompName + "-version]"
                                ]


                        processStep "Deploy Artifact",
                                processStepType: 'command',
                                subproject: '/plugins/EC-Core/project',
                                subprocedure: 'RunCommand',
                                actualParameter: [
                                        shellToUse: 'sh',
                                        commandToRun: 'sh $' + '[/myJob/retrievedArtifactVersions/$' + '[assignedResourceName]/$' + '[/myComponent/ec_content_details/artifactName]/cacheLocation]/installer.sh'
                                ],
                                applicationName: null,
                                applicationTierName: null,
                                componentApplicationName: AppName

                        processDependency "Retrieve Artifact",
                                targetProcessStepName: "Deploy Artifact"

                    } // process
                } // Components
                process "Deploy",{

                    processStep  "Install $CompName",
                            processStepType: 'process',
                            componentName: null,
                            componentApplicationName: AppName,
                            errorHandling: 'failProcedure',
                            subcomponent: CompName,
                            subcomponentApplicationName: AppName,
                            subcomponentProcess: "Install"

                    processStep 'Validate', {
                        errorHandling = 'failProcedure'
                        processStepType = 'manual'
                        notificationTemplate = 'ec_default_manual_retry_process_step_notification_template'
                        assignee = [
                                'admin',
                        ]
                    } // processStep

                    processStep 'Rollback',
                            rollbackType: 'environment',
                            processStepType: 'rollback',
                            errorHandling: 'abortJob'

                    processDependency "Install $CompName", targetProcessStepName: 'Validate', {
                        branchCondition = '$[/javascript !getProperty("/myJob/ec_rollbackCallerJobId")]'
                        branchConditionName = 'notOnRollback'
                        branchConditionType = 'CUSTOM'
                        branchType = 'ALWAYS'
                    }

                    processDependency 'Validate', targetProcessStepName: 'Rollback', {
                        branchType = 'ERROR'
                    }

                } // process
            } // applicationTier
        } // each Tier

        // Create Application-Environment mappings
        Envs.each { Env ->
            tierMap "$AppName-$Env",
                    environmentProjectName: projectName,
                    environmentName: Env,
                    tierMapping: AppEnvTiers
        } // each Env

    } // Applications

} // project

// Create publishArtifact procedure

project ProjectName, {
    procedure "Publish Artifact Versions", {
        formalParameter "artifactName", type: "entry", required: "1"
        formalParameter "artifactVersion", type: "entry", required: "1"
        formalParameter "fileName", type: "entry", required: "1"
        formalParameter "fileContent", type: "textarea", required: "1"

        step "Create File",
                subproject: "/plugins/EC-FileOps/project",
                subprocedure: "AddTextToFile",
                actualParameter: [
                        Path: '$' + "[fileName]",
                        Content: '$' + "[fileContent]",
                        AddNewLine: "0",
                        Append: "0"
                ]

        step "Publish Artifact",
                subproject: "/plugins/EC-Artifact/project",
                subprocedure: "Publish",
                actualParameter: [
                        artifactName: '$' + "[artifactName]",
                        artifactVersionVersion: '$' + "[artifactVersion]",
                        includePatterns: '$' + "[fileName]",
                        repositoryName: "Default"
                        //fromLocation:
                ]
    }
}

ArtifactVersions.each { ar ->
    // Create artifact version
    transaction {
        runProcedure procedureName: "Publish Artifact Versions", projectName: ProjectName,
                actualParameter: [
                        artifactName: ar.artifactName,
                        fileContent: "echo Installing " + ar.artifactName,
                        fileName: "installer.sh",
                        artifactVersion: ar.artifactVersion
                ]
    }
}
