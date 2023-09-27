#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest


if (-not (Test-Command docker) -and (-not (Get-Variable -Name PWSHRC_FORCE_MODULES_EXPORT_UNSUPPORTED -Scope Global -ValueOnly -ErrorAction SilentlyContinue))) {
    return
}

Set-Alias -Name dk -Value docker
Export-ModuleMember -Alias dk

function Get-DockerContainerLatest {
    docker ps -l @args --format json `
    | ConvertFrom-Json
}
Set-Alias -Name dklc -Value Get-DockerContainerLatest
Export-ModuleMember -Function Get-DockerContainerLatest -Alias dklc

function Get-DockerContainerLatestQuiet {
    docker ps -l -q @args
}
Set-Alias -Name dklcid -Value Get-DockerContainerLatestQuiet
Export-ModuleMember -Function Get-DockerContainerLatestQuiet -Alias dklcid

function Get-DockerContainerLatestIPAddress {
    docker inspect -f "{{.NetworkSettings.IPAddress}}" (Get-DockerContainerLatestQuiet)
}
Set-Alias -Name dklcip -Value Get-DockerContainerLatestIPAddress
Export-ModuleMember -Function Get-DockerContainerLatestIPAddress -Alias dklcip

function Get-DockerContainerRunning {
    docker ps @args --format json `
    | ConvertFrom-Json `
    | Select-Object -Property ID, Image, Command, CreatedSince, Status, Ports, Names `
    | Format-Table
}
Set-Alias -Name dkps -Value Get-DockerContainerRunning
Export-ModuleMember -Function Get-DockerContainerRunning -Alias dkps

function Get-DockerContainerAll {
    docker ps -a @args --format json `
    | ConvertFrom-Json `
    | Select-Object -Property ID, Image, Command, CreatedSince, Status, Ports, Names `
    | Format-Table
}
Set-Alias -Name dkpsa -Value Get-DockerContainerAll
Export-ModuleMember -Function Get-DockerContainerAll -Alias dkpsa

function Get-DockerImage {
    docker images @args --format json `
    | ConvertFrom-Json `
    | Select-Object -Property Repository, Tag, ID, CreatedSince, Size `
    | Format-Table
}
Set-Alias -Name dki -Value Get-DockerImage
Export-ModuleMember -Function Get-DockerImage -Alias dki

function Remove-DockerContainerAll {
    docker rm (docker ps -a -q) @args
}
Set-Alias -Name dkrmac -Value Remove-DockerContainerAll
Export-ModuleMember -Function Remove-DockerContainerAll -Alias dkrmac

function Remove-DockerUnusedImage {
    [string[]] $imageIds = (docker images -q -f dangling=true)
    if ($imageIds) {
        docker rmi $imageIds
    }
}
Set-Alias -Name dkrmui -Value Remove-DockerUnusedImage
Export-ModuleMember -Function Remove-DockerUnusedImage -Alias dkrmui

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
Export-ModuleMember -Function docker-remove-most-recent-container -Alias dkrmlc

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
Export-ModuleMember -Function docker-remove-stale-assets -Alias dkrmall

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
Export-ModuleMember -Function docker-remove-most-recent-image -Alias dkrmli

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
Export-ModuleMember -Function docker-remove-images -Alias dkrmi

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
Export-ModuleMember -Function docker-runtime-environment -Alias dkre

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
Export-ModuleMember -Function docker-enter-latest-container -Alias dkelc, dkbash

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
Export-ModuleMember -Function docker-remove-latest-container -Alias dkrmflast

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
Export-ModuleMember -Function docker-execute-in-container -Alias dkex

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
Export-ModuleMember -Function docker-run-in-container-transient -Alias dkri

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
Export-ModuleMember -Function docker-run-in-container-transient-with-mounted-cwd -Alias dkric

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
Export-ModuleMember -Function docker-run-in-container-transient-interactively -Alias dkrit

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
Export-ModuleMember -Function docker-run-in-container-transient-interactively-with-mounted-cwd -Alias dkritc

function docker-image-prune-all-forcefully {
    docker image prune -a -f
}
Set-Alias -Name dkip -Value docker-image-prune-all-forcefully
Export-ModuleMember -Function docker-image-prune-all-forcefully -Alias dkip

function docker-volume-prune-forcefully {
    docker volume prune -f
}
Set-Alias -Name dkvp -Value docker-volume-prune-forcefully
Export-ModuleMember -Function docker-volume-prune-forcefully -Alias dkvp

function docker-system-prune-all-forcefully {
    docker system prune -a -f
}
Set-Alias -Name dksp -Value docker-system-prune-all-forcefully
Export-ModuleMember -Function docker-system-prune-all-forcefully -Alias dksp

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
Export-ModuleMember -Function docker-enter

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
Export-ModuleMember -Function docker-archive-content

function docker-build {
    docker build @args
}
Set-Alias -Name dbl -Value docker-build
Export-ModuleMember -Function docker-build -Alias dbl

function docker-container-inspect {
    docker container inspect @args
}
Set-Alias -Name dcin -Value docker-container-inspect
Export-ModuleMember -Function docker-container-inspect -Alias dcin

function docker-container-list {
    docker container ls @args
}
Set-Alias -Name dcls -Value docker-container-list
Export-ModuleMember -Function docker-container-list -Alias dcls

function docker-container-list-all {
    docker container ls -a @args
}
Set-Alias -Name dclsa -Value docker-container-list-all
Export-ModuleMember -Function docker-container-list-all -Alias dclsa

function docker-image-build {
    docker image build @args
}
Set-Alias -Name dib -Value docker-image-build
Export-ModuleMember -Function docker-image-build -Alias dib

function docker-image-inspect {
    docker image inspect @args
}
Set-Alias -Name dii -Value docker-image-inspect
Export-ModuleMember -Function docker-image-inspect -Alias dii

function docker-image-list {
    docker image ls @args
}
Set-Alias -Name dils -Value docker-image-list
Export-ModuleMember -Function docker-image-list -Alias dils

function docker-image-push {
    docker image push @args
}
Set-Alias -Name dipu -Value docker-image-push
Export-ModuleMember -Function docker-image-push -Alias dipu

function docker-image-remove {
    docker image rm @args
}
Set-Alias -Name dirm -Value docker-image-remove
Export-ModuleMember -Function docker-image-remove -Alias dirm

function docker-image-tag {
    docker image tag @args
}
Set-Alias -Name dit -Value docker-image-tag
Export-ModuleMember -Function docker-image-tag -Alias dit

function docker-container-logs {
    docker container logs @args
}
Set-Alias -Name dlo -Value docker-container-logs
Export-ModuleMember -Function docker-container-logs -Alias dlo

function docker-network-create {
    docker network create @args
}
Set-Alias -Name dnc -Value docker-network-create
Export-ModuleMember -Function docker-network-create -Alias dnc

function docker-network-connect {
    docker network connect @args
}
Set-Alias -Name dncn -Value docker-network-connect
Export-ModuleMember -Function docker-network-connect -Alias dncn

function docker-network-disconnect {
    docker network disconnect @args
}
Set-Alias -Name dndcn -Value docker-network-disconnect
Export-ModuleMember -Function docker-network-disconnect -Alias dndcn

function docker-network-inspect {
    docker network inspect @args
}
Set-Alias -Name dni -Value docker-network-inspect
Export-ModuleMember -Function docker-network-inspect -Alias dni

function docker-network-list {
    docker network ls @args
}
Set-Alias -Name dnls -Value docker-network-list
Export-ModuleMember -Function docker-network-list -Alias dnls

function docker-network-remove {
    docker network rm @args
}
Set-Alias -Name dnrm -Value docker-network-remove
Export-ModuleMember -Function docker-network-remove -Alias dnrm

function docker-container-port-open {
    docker container port @args
}
Set-Alias -Name dpo -Value docker-container-port-open
Export-ModuleMember -Function docker-container-port-open -Alias dpo

function docker-pull {
    docker pull @args
}
Set-Alias -Name dpu -Value docker-pull
Export-ModuleMember -Function docker-pull -Alias dpu

function docker-container-run {
    docker container run @args
}
Set-Alias -Name dr -Value docker-container-run
Export-ModuleMember -Function docker-container-run -Alias dr

function docker-container-run-interactively {
    docker container run -it @args
}
Set-Alias -Name drit -Value docker-container-run-interactively
Export-ModuleMember -Function docker-container-run-interactively -Alias drit

function docker-container-remove {
    docker container rm @args
}
Set-Alias -Name drm -Value docker-container-remove
Export-ModuleMember -Function docker-container-remove -Alias drm

function docker-container-remove-forcefully {
    docker container rm -f @args
}
Set-Alias -Name drm! -Value docker-container-remove-forcefully
Export-ModuleMember -Function docker-container-remove-forcefully -Alias drm!

function docker-container-start {
    docker container start @args
}
Set-Alias -Name dst -Value docker-container-start
Export-ModuleMember -Function docker-container-start -Alias dst

function docker-container-restart {
    docker container restart @args
}
Set-Alias -Name drs -Value docker-container-restart
Export-ModuleMember -Function docker-container-restart -Alias drs

function docker-container-stop-all {
    docker container stop (docker ps -q)
}
Set-Alias -Name dsta -Value docker-container-stop-all
Export-ModuleMember -Function docker-container-stop-all -Alias dsta

function docker-container-stop {
    docker container stop @args
}
Set-Alias -Name dstp -Value docker-container-stop
Export-ModuleMember -Function docker-container-stop -Alias dstp

function docker-top {
    docker top @args
}
Set-Alias -Name dtop -Value docker-top
Export-ModuleMember -Function docker-top -Alias dtop

function docker-volume-inspect {
    docker volume inspect @args
}
Set-Alias -Name dvi -Value docker-volume-inspect
Export-ModuleMember -Function docker-volume-inspect -Alias dvi

function docker-volume-list {
    docker volume ls @args
}
Set-Alias -Name dvls -Value docker-volume-list
Export-ModuleMember -Function docker-volume-list -Alias dvls

function docker-volume-prune {
    docker volume prune @args
}
Set-Alias -Name dvprune -Value docker-volume-prune
Export-ModuleMember -Function docker-volume-prune -Alias dvprune

function docker-container-execute {
    docker container exec @args
}
Set-Alias -Name dxc -Value docker-container-execute
Export-ModuleMember -Function docker-container-execute -Alias dxc

function docker-container-execute-interactively {
    docker container exec -it @args
}
Set-Alias -Name dxcit -Value docker-container-execute-interactively
Export-ModuleMember -Function docker-container-execute-interactively -Alias dxcit
