#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
#Requires -Modules @{ ModuleName = "poshy-lucidity"; RequiredVersion = "0.4.1" }


if (-not (Test-Command docker) -and (-not (Get-Variable -Name PWSHRC_FORCE_MODULES_EXPORT_UNSUPPORTED -Scope Global -ValueOnly -ErrorAction SilentlyContinue))) {
    return
}

Set-Alias -Name dk -Value docker

function Get-DockerContainerLatest {
    docker ps -l @args --format json `
    | ConvertFrom-Json
}
Set-Alias -Name dklc -Value Get-DockerContainerLatest

function Get-DockerContainerLatestQuiet {
    docker ps -l -q @args
}
Set-Alias -Name dklcid -Value Get-DockerContainerLatestQuiet

function Get-DockerContainerLatestIPAddress {
    docker inspect -f "{{.NetworkSettings.IPAddress}}" (Get-DockerContainerLatestQuiet)
}
Set-Alias -Name dklcip -Value Get-DockerContainerLatestIPAddress

function Get-DockerContainerRunning {
    docker ps @args --format json `
    | ConvertFrom-Json `
    | Select-Object -Property ID, Image, Command, CreatedSince, Status, Ports, Names `
    | Format-Table
}
Set-Alias -Name dkps -Value Get-DockerContainerRunning

function Get-DockerContainerAll {
    docker ps -a @args --format json `
    | ConvertFrom-Json `
    | Select-Object -Property ID, Image, Command, CreatedSince, Status, Ports, Names `
    | Format-Table
}
Set-Alias -Name dkpsa -Value Get-DockerContainerAll

function Get-DockerImage {
    docker images @args --format json `
    | ConvertFrom-Json `
    | Select-Object -Property Repository, Tag, ID, CreatedSince, Size `
    | Format-Table
}
Set-Alias -Name dki -Value Get-DockerImage

function Remove-DockerContainerAll {
    docker rm (docker ps -a -q) @args
}
Set-Alias -Name dkrmac -Value Remove-DockerContainerAll

function Remove-DockerUnusedImage {
    [string[]] $imageIds = (docker images -q -f dangling=true)
    if ($imageIds) {
        docker rmi $imageIds
    }
}
Set-Alias -Name dkrmui -Value Remove-DockerUnusedImage

<#
.SYNOPSIS
    Delete most recent (i.e., last) Docker container.
.COMPONENT
    Docker
#>
function docker-remove-most-recent-container {
    docker ps -ql | xargs docker rm
}
Set-Alias -Name dkrmlc -Value docker-remove-most-recent-container

<#
.SYNOPSIS
    Delete exited containers and dangling images.
.COMPONENT
    Docker
#>
function docker-remove-stale-assets {
    docker ps --filter status=exited -q | xargs docker rm --volumes
    docker images --filter dangling=true -q | xargs docker rmi
}
Set-Alias -Name dkrmall -Value docker-remove-stale-assets

<#
.SYNOPSIS
    Delete most recent (i.e., last) Docker image.
.COMPONENT
    Docker
#>
function docker-remove-most-recent-image {
    docker images -q | head -1 | xargs docker rmi
}
Set-Alias -Name dkrmli -Value docker-remove-most-recent-image

<#
.SYNOPSIS
    Remove images with supplied tags or all if no tags are supplied.
.EXAMPLE
    docker-remove-images
.EXAMPLE
    docker-remove-images ubuntu
.EXAMPLE
    docker-remove-images ubuntu:latest
.EXAMPLE
    docker-remove-images ubuntu:latest ubuntu:trusty
.EXAMPLE
    docker-remove-images $(docker images -q)
.EXAMPLE
    docker-remove-images $(docker images -q ubuntu)
.EXAMPLE
    docker-remove-images $(docker images -q ubuntu:latest ubuntu:trusty)
.COMPONENT
    Docker
#>
function docker-remove-images {
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromRemainingArguments = $true )]
        [string[]] $dockerImage
    )

    if (-not $dockerImage) {
        docker rmi $(docker images -q)
        return
    }

    $extantDockerImages = (docker images --format json | ConvertFrom-Json)
    $dockerImageIds = @()
    foreach ($image in $dockerImage) {
        $dockerImageIds += `
            $extantDockerImages `
            | Where-Object { ($image -eq $_.ID) -or ($image -eq $_.Repository) -or ($image -eq $_.Repository+":"+$_.Tag) } `
            | Select-Object -ExpandProperty ID
    }
    $dockerImageIds = ($dockerImageIds | Select-Object -Unique)

    if ($dockerImageIds) {
        docker rmi @dockerImageIds
    }
}
Set-Alias -Name dkrmi -Value docker-remove-images

<#
.SYNOPSIS
    List the environmental variables of the supplied image ID.
.COMPONENT
    Docker
#>
function docker-runtime-environment {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerImage
    )
    docker run $dockerImage env
}
Set-Alias -Name dkre -Value docker-runtime-environment

<#
.SYNOPSIS
    Enter the latest docker container.
.COMPONENT
    Docker
#>
function docker-enter-latest-container {
    docker exec -it (Get-DockerContainerLatestQuiet) bash --login
}
Set-Alias -Name dkelc -Value docker-enter-latest-container
Set-Alias -Name dkbash -Value 'docker-enter-latest-container'

<#
.SYNOPSIS
    Remove the latest docker container.
.COMPONENT
    Docker
#>
function docker-remove-latest-container {
    docker rm -f $(Get-DockerContainerLatestQuiet)
}
Set-Alias -Name dkrmflast -Value 'docker-remove-latest-container'

<#
.SYNOPSIS
    Executes the given command in the given container.
.EXAMPLE
    docker-execute-in-container oracle-xe 'ls -l /u01/app/oracle/oradata'
.COMPONENT
    Docker
#>
function docker-execute-in-container {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerContainer,

        [Parameter(Mandatory = $true, Position = 1)]
        [string] $command
    )
    docker exec -it $dockerContainer $command
}
Set-Alias -Name dkex -Value docker-execute-in-container

<#
.SYNOPSIS
    Runs the given command in the given container, then removes the container afterward.
.EXAMPLE
    docker-run-in-container-transient oracle-xe 'ls -l /u01/app/oracle/oradata'
.COMPONENT
    Docker
#>
function docker-run-in-container-transient {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerContainer,

        [Parameter(Mandatory = $true, Position = 1)]
        [string] $command
    )
    docker run --rm -i $dockerContainer $command
}
Set-Alias -Name dkri -Value docker-run-in-container-transient

<#
.SYNOPSIS
    Runs the given command in the given container, while mounting the current working directory as the container's working directory.
.COMPONENT
    Docker
#>
function docker-run-in-container-transient-with-mounted-cwd {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerContainer,

        [Parameter(Mandatory = $true, Position = 1)]
        [string] $command
    )
    docker run --rm -i -v ${PWD}:/cwd -w /cwd $dockerContainer $command
}
Set-Alias -Name dkric -Value docker-run-in-container-transient-with-mounted-cwd

function docker-run-in-container-transient-interactively {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerContainer,

        [Parameter(Mandatory = $true, Position = 1)]
        [string] $command
    )
    docker run --rm -it $dockerContainer $command
}
Set-Alias -Name dkrit -Value docker-run-in-container-transient-interactively

function docker-run-in-container-transient-interactively-with-mounted-cwd {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerContainer,

        [Parameter(Mandatory = $true, Position = 1)]
        [string] $command
    )
    docker run --rm -it -v ${PWD}:/cwd -w /cwd $dockerContainer $command
}
Set-Alias -Name dkritc -Value docker-run-in-container-transient-interactively-with-mounted-cwd

function docker-image-prune-all-forcefully {
    docker image prune -a -f
}
Set-Alias -Name dkip -Value docker-image-prune-all-forcefully

function docker-volume-prune-forcefully {
    docker volume prune -f
}
Set-Alias -Name dkvp -Value docker-volume-prune-forcefully

function docker-system-prune-all-forcefully {
    docker system prune -a -f
}
Set-Alias -Name dksp -Value docker-system-prune-all-forcefully

<#
.SYNOPSIS
    Enter the specified docker container using bash.
.EXAMPLE
    docker-enter oracle-xe
.COMPONENT
    Docker
#>
function docker-enter {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerContainer
    )
    docker exec -it $dockerContainer /bin/bash;
}

<#
.SYNOPSIS
    Show the content of the provided Docker image archive.
.EXAMPLE
    docker-archive-content images.tar.gz
.COMPONENT
    Docker
#>
function docker-archive-content() {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $dockerImageArchive
    )

    tar -xzOf $dockerImageArchive manifest.json | jq '[.[] | .RepoTags] | add'
}

function docker-build {
    docker build @args
}
Set-Alias -Name dbl -Value docker-build

function docker-container-inspect {
    docker container inspect @args
}
Set-Alias -Name dcin -Value docker-container-inspect

function docker-container-list {
    docker container ls @args
}
Set-Alias -Name dcls -Value docker-container-list

function docker-container-list-all {
    docker container ls -a @args
}
Set-Alias -Name dclsa -Value docker-container-list-all

function docker-image-build {
    docker image build @args
}
Set-Alias -Name dib -Value docker-image-build

function docker-image-inspect {
    docker image inspect @args
}
Set-Alias -Name dii -Value docker-image-inspect

function docker-image-list {
    docker image ls @args
}
Set-Alias -Name dils -Value docker-image-list

function docker-image-push {
    docker image push @args
}
Set-Alias -Name dipu -Value docker-image-push

function docker-image-remove {
    docker image rm @args
}
Set-Alias -Name dirm -Value docker-image-remove

function docker-image-tag {
    docker image tag @args
}
Set-Alias -Name dit -Value docker-image-tag

function docker-container-logs {
    docker container logs @args
}
Set-Alias -Name dlo -Value docker-container-logs

function docker-network-create {
    docker network create @args
}
Set-Alias -Name dnc -Value docker-network-create

function docker-network-connect {
    docker network connect @args
}
Set-Alias -Name dncn -Value docker-network-connect

function docker-network-disconnect {
    docker network disconnect @args
}
Set-Alias -Name dndcn -Value docker-network-disconnect

function docker-network-inspect {
    docker network inspect @args
}
Set-Alias -Name dni -Value docker-network-inspect

function docker-network-list {
    docker network ls @args
}
Set-Alias -Name dnls -Value docker-network-list

function docker-network-remove {
    docker network rm @args
}
Set-Alias -Name dnrm -Value docker-network-remove

function docker-container-port-open {
    docker container port @args
}
Set-Alias -Name dpo -Value docker-container-port-open

function docker-pull {
    docker pull @args
}
Set-Alias -Name dpu -Value docker-pull

function docker-container-run {
    docker container run @args
}
Set-Alias -Name dr -Value docker-container-run

function docker-container-run-interactively {
    docker container run -it @args
}
Set-Alias -Name drit -Value docker-container-run-interactively

function docker-container-remove {
    docker container rm @args
}
Set-Alias -Name drm -Value docker-container-remove

function docker-container-remove-forcefully {
    docker container rm -f @args
}
Set-Alias -Name drm! -Value docker-container-remove-forcefully

function docker-container-start {
    docker container start @args
}
Set-Alias -Name dst -Value docker-container-start

function docker-container-restart {
    docker container restart @args
}
Set-Alias -Name drs -Value docker-container-restart

function docker-container-stop-all {
    docker container stop (docker ps -q)
}
Set-Alias -Name dsta -Value docker-container-stop-all

function docker-container-stop {
    docker container stop @args
}
Set-Alias -Name dstp -Value docker-container-stop

function docker-top {
    docker top @args
}
Set-Alias -Name dtop -Value docker-top

function docker-volume-inspect {
    docker volume inspect @args
}
Set-Alias -Name dvi -Value docker-volume-inspect

function docker-volume-list {
    docker volume ls @args
}
Set-Alias -Name dvls -Value docker-volume-list

function docker-volume-prune {
    docker volume prune @args
}
Set-Alias -Name dvprune -Value docker-volume-prune

function docker-container-execute {
    docker container exec @args
}
Set-Alias -Name dxc -Value docker-container-execute

function docker-container-execute-interactively {
    docker container exec -it @args
}
Set-Alias -Name dxcit -Value docker-container-execute-interactively


Export-ModuleMember -Function * -Alias *
