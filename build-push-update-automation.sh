#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
#set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

function errtrap {
  es=$?
  echo "ERROR line $1: Command exited with status $es."
}

trap 'errtrap $LINENO' ERR  # is run whenever a command in the surrounding script or function exits with non-zero status

# Use in the the functions: eval $invocation
invocation='say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${normal:-}"'

# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

verbose=true
args=("$@")
SECONDS=0
current_dir=""
services="id-web,id-api,id-ums,bi-web,bi-api,bi-jobs,bi-dataservice"
tag=""
namespace="default"
base="ubuntu"
actions="build,push,update"
registry="development"
image_repo=""
package=""
version="4.2.x"
build_context_path=""
package_file_name=""
unzip_output=""
cluster=""
kube_config=""
work_dir=""
#ci_proj_4_1="boldbi-ci-4-1"
ci_proj_4_2="boldbi-ci"
appdatafiles_4_2="/output/installutils"
#appdatafiles_4_1="/output/MoveSharedFiles"
shell_scripts_4_2="/installutils/installutils/shell_scripts"
shell_scripts_4_1="/MoveSharedFiles/MoveSharedFiles/shell_scripts"
product_json=""
engineer="Rahul Subash"
customer="unknown"
publishType="Package"
deploymentType="Kubernetes"

while [ $# -ne 0 ]
do
    name="$1"
    case "$name" in
        -s|--services)
            shift
            services="$1"
            ;;

                -t|--tag)
            shift
            tag="$1"
            ;;

                -n|--namespace)
            shift
            namespace="$1"
            ;;

                -b|--base)
            shift
            base="$1"
            ;;

                -a|--actions)
            shift
                        actions="$1"
            ;;

                -r|--registry)
            shift
                        registry="$1"
            ;;

                -p|--package)
            shift
                        package="$1"
            ;;

                -v|--version)
            shift
                        version="$1"
            ;;

                -e|--engineer)
            shift
                        engineer="$1"
            ;;

                -c|--customer)
            shift
                        customer="$1"
            ;;

                -d|--deployment)
            shift
                        deploymentType="$1"
            ;;

        -?|--?|--help|-[Hh]elp)
            script_name="$(basename "$0")"
            echo "Bold BI Installer"
            echo "Usage: $script_name [-u|--user <USER>]"
            echo "       $script_name |-?|--help"
            echo ""
            exit 0
            ;;
        *)
            say_err "Unknown argument \`$name\`"
            exit 1
            ;;
    esac

    shift
done

# Setup some colors to use. These need to work in fairly limited shells, like the Ubuntu Docker container where there are only 8 colors.
# See if stdout is a terminal
if [ -t 1 ] && command -v tput > /dev/null; then
    # see if it supports colors
    ncolors=$(tput colors)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        bold="$(tput bold       || echo)"
        normal="$(tput sgr0     || echo)"
        black="$(tput setaf 0   || echo)"
        red="$(tput setaf 1     || echo)"
        green="$(tput setaf 2   || echo)"
        yellow="$(tput setaf 3  || echo)"
        blue="$(tput setaf 4    || echo)"
        magenta="$(tput setaf 5 || echo)"
        cyan="$(tput setaf 6    || echo)"
        white="$(tput setaf 7   || echo)"
    fi
fi

say_warning() {
    printf "%b\n" "${yellow:-}multi-image-publish automation: Warning: $1${normal:-}" >&3
}

say_err() {
    printf "%b\n" "${red:-}multi-image-publish automation: Error: $1${normal:-}" >&2
}

say_success() {
    printf "%b\n" "${green:-}multi-image-publish automation: Success: $1${normal:-}" >&2
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
    printf "%b\n" "${cyan:-}multi-image-publish automation:${normal:-} $1" >&3
}

say_verbose() {
    if [ "$verbose" = true ]; then
        say "$1"
    fi
}

machine_has() {
    eval $invocation

    hash "$1" > /dev/null 2>&1
    return $?
}

# args:
# input - $1
remove_trailing_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input%/}"
    return 0
}

# args:
# input - $1
remove_beginning_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input#/}"
    return 0
}

check_min_req() {
    eval $invocation

    [ -n "$tag" ] || read -p 'Enter the image tag to build: ' tag

        if [ -z "$base" ]
        then
                base="ubuntu"
        fi

        if [ -z "$registry" ]
        then
                base="development"
        fi

        if [ "$registry" = "development" ]; then
                image_repo="boldbi-dev-296107"
        elif [ "$registry" = "production" ]; then
                image_repo="boldbi-294612"
        fi

        if [[ "$version" == *"6"* || "$version" == *"6.16"* || "$version" == *"6.13"* || "$version" == *"7.1"* || "$version" == *"6.8"* ]]
        then
            package_file_name="../kubernetes/4-2_packages/BoldBIEnterpriseEdition_Linux_$version.zip"
            unzip_output="../kubernetes/4-2_packages/BoldBIEnterpriseEdition_Linux_$version"
            build_context_path="$unzip_output/BoldBIEnterpriseEdition-Linux/"
        elif [[ "$version" == *"4.1"* ]]
        then
            package_file_name="../kubernetes/4-1_packages/BoldBIEnterpriseEdition_Linux_$version.zip"
                unzip_output="../kubernetes/4-1_packages/BoldBIEnterpriseEdition_Linux_$version"
            build_context_path="$unzip_output/BoldBIEnterpriseEdition-Linux/"
        fi

        if [ ! -z "$package" ]
        then
                        download_package
                        unzip_package
        fi
}

download_package() {
    eval $invocation
        if [[ $deploymentType == "docker" || $deploymentType == "Docker" ]]; then
                package_file_name="../docker/4-2_packages/BoldBIEnterpriseEdition_Linux_$version.zip"
                unzip_output="../docker/4-2_packages/BoldBIEnterpriseEdition_Linux_$version"
        if [ -f $package_file_name ]; then
            say_warning "Package already exist. Skipping download..."
        else
            wget -O $package_file_name $package
        fi
    else
        if [ -f $package_file_name ]; then
            say_warning "Package already exist. Skipping download..."
        else
            wget -O $package_file_name $package
        fi
        fi
}

unzip_package() {
    eval $invocation
        if [ -d $unzip_output ]; then
            say_warning "Package already unzipped. Skipping unzip process..."
        else
        unzip $package_file_name -d $unzip_output
        fi
}

move_shared_files() {
    eval $invocation

        current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        #$unzip_output=../kubernetes/4-2_packages/BoldBIEnterpriseEdition_Linux_$version
        if [[ "$version" == *"6"* || "$version" == *"6.5"* || "$version" == *"6.16"* || "$version" == *"7.1"* || "$version" == *"6.8"* ]]
        then
            work_dir="$unzip_output/BoldBIEnterpriseEdition-Linux/application"

                if [ ! -f "$build_context_path/boldbi-designer.txt" ]; then
                    if [ $base == "ubuntu" ]; then cp -a 4-2_dockerfiles/ubuntu/* $build_context_path; fi
                        if [ $base == "debian" ]; then cp -a 4-2_dockerfiles/debian/* $build_context_path; fi
            fi
        elif [[ "$version" == *"4.1"* ]]
        then
            work_dir="$unzip_output/BoldBIEnterpriseEdition-Linux/boldbi"

                if [ ! -f "$build_context_path/boldbi-designer.txt" ]; then
                    if [ $base == "ubuntu" ]; then cp -a 4-1_dockerfiles/ubuntu/* $build_context_path; fi
                        if [ $base == "debian" ]; then cp -a 4-1_dockerfiles/debian/* $build_context_path; fi
            fi
        fi
        #work_dir= ../kubernetes/4-2_packages/BoldBIEnterpriseEdition_Linux_$version/BoldBIEnterpriseEdition-Linux/application
        package_appdatafiles="$work_dir/idp/web/appdatafiles"
        chromium_dir="$work_dir/bi/dataservice/k8s_chromium"
        appdatafiles="$ci_proj_4_2$appdatafiles_4_2"
        shell_scripts="$ci_proj_4_2$shell_scripts_4_2"
        product_json="$package_appdatafiles/installutils/app_data"
        #appdatafiles= boldbi-ci/output/installutils
        if [ ! -d $package_appdatafiles ]; then
            mkdir $package_appdatafiles
        say "Copying appdatafiles to $package_appdatafiles"
        cp -a $appdatafiles $package_appdatafiles
        fi
    #shell_scripts= boldbi-ci/installutils/installutils/shell_scripts
        if [ ! -f "$work_dir/idp/web/entrypoint.sh" ]; then
            say "Copying idp scripts to $work_dir/idp/web/"
            cp -a "$shell_scripts/id_web/entrypoint.sh" "$work_dir/idp/web/"
        fi

        if [ ! -f "$work_dir/bi/dataservice/entrypoint.sh" ]; then
            say "Copying designer scripts to $work_dir/bi/designer/"
            cp -a "$shell_scripts/designer/entrypoint.sh" "$work_dir/bi/dataservice/"
        fi

        if [ ! -f "$work_dir/bi/dataservice/install-optional.libs.sh" ]; then
        cp -a "$shell_scripts/designer/install-optional.libs.sh" "$work_dir/bi/dataservice/"
        fi

        if [ ! -f "$product_json/configuration/product.json" ]; then
            say "Copying product.json file to $product_json/configuration"
            cp -a "$work_dir/app_data/configuration" $product_json
        fi

        if [ ! -f "$product_json/optional-libs/MongoDB.Driver.dll" ]; then
            say "Un-zipping clientlibrary.zip to $product_json/optional-libs/"
            unzip "$unzip_output/BoldBIEnterpriseEdition-Linux/clientlibrary/clientlibrary.zip" -d "$product_json/optional-libs/"
        fi
}

login_to_image_repo() {
   eval $invocation
        gcloud auth activate-service-account boldreports@boldbi-dev-296107.iam.gserviceaccount.com --key-file=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/boldreports-service-account.json
        say_success "Login successful for $image_repo account"
}

generate_post_data()
{
  cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "0076D7",
    "summary": "Image Published Completed",
    "sections": [{
        "activityTitle": "Image Publish Completed",
                "activitySubtitle": "Status: Success",
        "activityImage": "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRpw2PmhjPN8AmnHsPfulMstzCLkI-wKIbg6Q&usqp=CAU",
        "facts": [{
            "name": "Customer",
            "value": "$customer"
        },
                {
            "name": "Requested by",
            "value": "$engineer"
        },
                {
            "name": "Deployment type",
            "value": "$deploymentType"
        }, {
            "name": "Publish type",
            "value": "$publishType"
        }, {
            "name": "Image Tag",
            "value": "$tag"
        }],
        "markdown": true
    }]
}
EOF
}

build_push_update() {
        date
    eval $invocation

        check_min_req

        move_shared_files

        if [[ "$actions" == *"push"* ]]; then login_to_image_repo; fi

        IFS=',' read -r -a buildactions <<< "$actions"
    IFS=',' read -r -a appnames <<< "$services"

        cd $build_context_path

        for act in "${buildactions[@]}"
        do

        case $act in
        "build")

        for app in "${appnames[@]}"
        do

        case $app in
        "id-web")
        docker build -t gcr.io/$image_repo/bold-identity:$tag -f boldbi-identity.txt .
        ;;
        "id-api")
        docker build -t gcr.io/$image_repo/bold-identity-api:$tag -f boldbi-identity-api.txt .
        ;;
        "id-ums")
        docker build -t gcr.io/$image_repo/bold-ums:$tag -f boldbi-ums.txt .
        ;;
        "bi-web")
        docker build -t gcr.io/$image_repo/boldbi-server:$tag -f boldbi-server.txt .
        ;;
        "bi-api")
        docker build -t gcr.io/$image_repo/boldbi-server-api:$tag -f boldbi-server-api.txt .
        ;;
        "bi-jobs")
        docker build -t gcr.io/$image_repo/boldbi-server-jobs:$tag -f boldbi-server-jobs.txt .
        ;;
        "bi-dataservice")
        #if [[ "$version" == *"4.2"* ]]
        #then
                #docker build -t gcr.io/$image_repo/boldbi-designer:$tag -f boldbi-designer-4-2.txt .
        #else
        docker build -t gcr.io/$image_repo/boldbi-designer:$tag -f boldbi-designer.txt .
        #fi
        ;;
        esac

    say_success "$app image Created Successfully"

        done

        ;;
        "push")

        for app in "${appnames[@]}"
        do

        case $app in
        "id-web")
        docker push gcr.io/$image_repo/bold-identity:$tag
        ;;
        "id-api")
        docker push gcr.io/$image_repo/bold-identity-api:$tag
        ;;
        "id-ums")
        docker push gcr.io/$image_repo/bold-ums:$tag
        ;;
        "bi-web")
        docker push gcr.io/$image_repo/boldbi-server:$tag
        ;;
        "bi-api")
        docker push gcr.io/$image_repo/boldbi-server-api:$tag
        ;;
        "bi-jobs")
        docker push gcr.io/$image_repo/boldbi-server-jobs:$tag
        ;;
        "bi-dataservice")
        docker push gcr.io/$image_repo/boldbi-designer:$tag
        ;;
        esac

    say_success "$app image pushed to $image_repo registry Successfully"

        done

        ;;
        "update")

    # if [ -z $cluster ]; then
            # $kube_config="kubectl"
        # elif [ $cluster == "aks" ]; then
            # $kube_config="kubectl --kubeconfig='D:\Confidential\cluster_config\k8s-yokogawa-test.config'"
        # fi

        for app in "${appnames[@]}"
        do

        case $app in
        "id-web")
        kubectl --kubeconfig=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/k8s-yokogawa-test.config set image deployment/id-web-deployment id-web-container=gcr.io/$image_repo/bold-identity:$tag --namespace=$namespace --record
        ;;
        "id-api")
        kubectl --kubeconfig=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/k8s-yokogawa-test.config set image deployment/id-api-deployment id-api-container=gcr.io/$image_repo/bold-identity-api:$tag --namespace=$namespace --record
        ;;
        "id-ums")
        kubectl --kubeconfig=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/k8s-yokogawa-test.config set image deployment/id-ums-deployment id-ums-container=gcr.io/$image_repo/bold-ums:$tag --namespace=$namespace --record
        ;;
        "bi-web")
        kubectl --kubeconfig=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/k8s-yokogawa-test.config set image deployment/bi-web-deployment bi-web-container=gcr.io/$image_repo/boldbi-server:$tag --namespace=$namespace --record
        ;;
        "bi-api")
        kubectl --kubeconfig=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/k8s-yokogawa-test.config set image deployment/bi-api-deployment bi-api-container=gcr.io/$image_repo/boldbi-server-api:$tag --namespace=$namespace --record
        ;;
        "bi-jobs")
        kubectl --kubeconfig=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/k8s-yokogawa-test.config set image deployment/bi-jobs-deployment bi-jobs-container=gcr.io/$image_repo/boldbi-server-jobs:$tag --namespace=$namespace --record
        ;;
        "bi-dataservice")
        kubectl --kubeconfig=/home/boldbi/DockerImageCreation/ImagePublishing/Confidential/k8s-yokogawa-test.config set image deployment/bi-dataservice-deployment bi-dataservice-container=gcr.io/$image_repo/boldbi-designer:$tag --namespace=$namespace --record
        ;;
        esac

        done

        ;;
        esac

        done

        send_webhook_notification

        date
        duration=$SECONDS
        echo "Elapsed Time: $(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
}

send_webhook_notification() {
        eval $invocation

        ## Send MS Teams Webhook notification
        ##curl -H 'Content-Type: application/json' -d '{"text": "Kubernetes image publish completed successfully. Tag: $tag"}' https://syncfusion.webhook.office.com/webhookb2/96b202bb-3763-47ab-bfd6-ec000b5c6adf@77f1fe12-b049-4919-8c50-9fb41e5bb63b/IncomingWebhook/f2140b4e21c241bf994f5c0074392941/009ab53f-8471-42ed-a5c3-093436390803  

        if [[ "$services" == "id-web,id-api,id-ums,bi-web,bi-api,bi-jobs,bi-dataservice" ]]; then
                publishType="Package Publish"
        else
                publishType="Patch Update"
        fi

        curl -H 'Content-Type: application/json' \
                -d "$(generate_post_data)" \
                https://syncfusion.webhook.office.com/webhookb2/96b202bb-3763-47ab-bfd6-ec000b5c6adf@77f1fe12-b049-4919-8c50-9fb41e5bb63b/IncomingWebhook/f2140b4e21c241bf994f5c0074392941/009ab53f-8471-42ed-a5c3-093436390803
}


docker_build_push() {
    eval $invocation
        date

        check_min_req

        if [[ "$actions" == *"push"* ]]; then login_to_image_repo; fi

        if [ -z "$actions" ]
        then
                actions="move-files,build,push"
        fi

        if [ "$registry" = "development" ]; then
                registry="gcr.io/boldbi-dev-296107/boldbi-docker"
        elif [ "$registry" = "production" ]; then
                registry="gcr.io/boldbi-294612/boldbi"
        elif [ "$registry" = "dockerhub" ]; then
                registry="syncfusion/boldbi"
        fi

        if [ "$base" = "debian" ]; then
                base="boldbi-debian"
        elif [ "$base" = "arm64" ]; then
                base="boldbi-debian-arm64"
        elif [ "$base" = "alpine" ]; then
                base="boldbi-alpine"
        elif [ "$base" = "ubuntu" ]; then
                base="boldbi-ubuntu"
        fi

        IFS=',' read -r -a appnames <<< "$base"

        if [[ "$version" == *"6"* || "$version" == *"6.6"* || "$version" == *"6.16"* || "$version" == *"7.1"* || "$version" == *"6.13"* || "$version" == *"6.8"* ]]    
        then
                build_dir="../docker/4-2_packages/BoldBIEnterpriseEdition_Linux_$version/BoldBIEnterpriseEdition-Linux"
                work_dir="$build_dir/application"
        else
                build_dir="../docker/4-1_packages/BoldBIEnterpriseEdition_Linux_$version/BoldBIEnterpriseEdition-Linux"
                work_dir="$build_dir/boldbi"
        fi

        IFS=',' read -r -a buildactions <<< "$actions"

        for act in "${buildactions[@]}"
        do

        case $act in
        "move-files")
        ### Move shared files
        echo "moving shared files"
        if [ ! -d "$build_dir/docker_build_tools" ]; then cp -a "docker_build_tools" $build_dir; fi
        if [ ! -d "$work_dir/clientlibrary" ]; then cp -a "docker_build_tools/boldbi/clientlibrary" $work_dir; fi
        if [ ! -f "$work_dir/boldbi-nginx-config" ]; then cp -a "docker_build_tools/boldbi/boldbi-nginx-config" $work_dir; fi
        if [ ! -f "$work_dir/chrome-linux.zip" ]; then wget -P "$work_dir" https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64/901912/chrome-linux.zip; fi
        if [ $base == "boldbi-alpine" ]; then
           cp -r "docker_build_tools/boldbi/alpine/entrypoint.sh" $work_dir
        else
           cp -r "docker_build_tools/boldbi/entrypoint.sh" $work_dir
        fi
        #if [ ! -f "$work_dir/entrypoint.sh" ]; then cp -a "docker_build_tools/boldbi/entrypoint.sh" $work_dir; fi
        if [ ! -f "$work_dir/product.json" ]; then cp -a "$work_dir/app_data/configuration/product.json" $work_dir; fi
        if [ -f "$work_dir/product.json" ]; then
                if ! grep -qF "host.docker.internal" $work_dir/product.json; then
                        sed -i 's|localhost:51894|localhost|g' $work_dir/product.json
                        sed -i 's|https://localhost:44349|http://localhost|g' $work_dir/product.json
                        sed -i 's|localhost:5000|localhost|g' $work_dir/product.json
                fi
        fi
        if [ ! -f "$work_dir/clientlibrary/MongoDB.Driver.dll" ]; then unzip "$build_dir/clientlibrary/clientlibrary.zip" -d "$work_dir/clientlibrary/"; fi
        if [ -d "$work_dir/app_data" ]; then rm -rf "$work_dir/app_data"; fi
        ;;

        "build")

        ### Move shared files
        echo "moving shared files"
        if [ ! -d "$build_dir/docker_build_tools" ]; then cp -a "docker_build_tools" $build_dir; fi
        if [ ! -d "$work_dir/clientlibrary" ]; then cp -a "docker_build_tools/boldbi/clientlibrary" $work_dir; fi
        if [ ! -f "$work_dir/boldbi-nginx-config" ]; then cp -a "docker_build_tools/boldbi/boldbi-nginx-config" $work_dir; fi
        if [ ! -f "$work_dir/chrome-linux.zip" ]; then wget -P "$work_dir" https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64/901912/chrome-linux.zip; fi
        if [ $base == "boldbi-alpine" ]; then
           cp -r "docker_build_tools/boldbi/alpine/entrypoint.sh" $work_dir
        else
           cp -r "docker_build_tools/boldbi/entrypoint.sh" $work_dir
        fi
        #if [ ! -f "$work_dir/entrypoint.sh" ]; then cp -a "docker_build_tools/boldbi/entrypoint.sh" $work_dir; fi
        if [ ! -f "$work_dir/product.json" ]; then cp -a "$work_dir/app_data/configuration/product.json" $work_dir; fi
        if [ -f "$work_dir/product.json" ]; then
                if ! grep -qF "host.docker.internal" $work_dir/product.json; then
                        sed -i 's|localhost:51894|localhost|g' $work_dir/product.json
                        sed -i 's|https://localhost:44349|http://localhost|g' $work_dir/product.json
                        sed -i 's|localhost:5000|localhost|g' $work_dir/product.json
                fi
        fi
        if [ ! -f "$work_dir/clientlibrary/MongoDB.Driver.dll" ]; then unzip "$build_dir/clientlibrary/clientlibrary.zip" -d "$work_dir/clientlibrary/"; fi
        if [ -d "$work_dir/app_data" ]; then rm -rf "$work_dir/app_data"; fi

        cd "$build_dir/docker_build_tools"

        if [ $base = "all" ]; then
                docker build -t $registry:$tag -f docker_build_tools/dockerfiles/boldbi-debian.txt ../ &
                docker build -t $registry:$tag-arm64 -f docker_build_tools/dockerfiles/boldbi-debian-arm64.txt ../ &
                docker build -t $registry:$tag-alpine -f docker_build_tools/dockerfiles/boldbi-alpine.txt ../ &
                docker build -t $registry:$tag-focal -f docker_build_tools/dockerfiles/boldbi-ubuntu.txt ../
        else
                docker build -t $registry:$tag -f dockerfiles/$base.txt ../
        fi
        ;;

        "push")
        if [ $base = "all" ]; then
                docker push $registry:$tag &
                docker push $registry:$tag-arm64 &
                docker push $registry:$tag-alpine &
                docker push $registry:$tag-focal
        else
                docker push $registry:$tag
        fi

        ;;

        esac
        done

        send_webhook_notification

        date
        duration=$SECONDS
        echo "Elapsed Time: $(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
}


if [[ $deploymentType == "docker" || $deploymentType == "Docker" ]]; then
        docker_build_push
else
        build_push_update
fi
