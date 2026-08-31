#! /bin/bash
#
# Script for build kubevirt customized image for WSF worklaod.
# Method 1: build kubevirt source code in buils process, and add new tag then push to registry.
# Method 2: The kubeivrt customized image were built by developer, and stored in artifactory website, and it's free for internal download without any credential.
#           Then just need to download and add new tag then push to registry.
# Currently, we adopt method 2 due to the complex of the kubevirt build.

KUBEVIRT_VHOST_VERSION=${KUBEVIRT_VHOST_VERSION:-"VIRTIO_V2_R"} # The customized kubevirt release version
REGISTRY_PORT=${PORT:-"5000"} # registry port
REGISTRY_IP="10.67.115.219" # default registry
OLD_DOCKER_REGISTRY="${REGISTRY_IP}:${REGISTRY_PORT}/"
REGISTRY=${REGISTRY:-"$REGISTRY_IP:$REGISTRY_PORT/"}
#IMAGE_TAG=${IMAGE_TAG:-latest}
BACKEND=${BACKEND:-kubernetes}
IMAGE_TAG=${RELEASE:-":test"} # Tag the RELEASE as a new tag
#kubevirt_package="kubevirt-virtIO-${KUBEVIRT_VHOST_VERSION}.tgz" # for full package
kubevirt_package="kubevirt-virtIO-${KUBEVIRT_VHOST_VERSION}.tar.gz"
downloadUri=${downloadUri:-"https://af01p-igk.devtools.intel.com/artifactory/platform_hero-igk-local/hero_features_assets/Edge/Storage/kubevirt/${kubevirt_package}"}
TMP_DIR=${TMP_DIR:-"/tmp/image_tar"}

mkdir -p ${TMP_DIR}
rm -rf ${TMP_DIR}/*

# cat /etc/redhat-release
# if [ $? -ne 0 ]; then
#     echo "Os is not centos"
# else
#     echo "Os is centos"
#     yum install -y wget
# fi

docker --version
if [ $? -ne 0 ]; then
    echo "Please install docker-ce first."
    # clean up the environment
    rm -rf ${TMP_DIR}
    exit 1
fi

echo "Fetch the kubevirt customized docker images..."
wget  $downloadUri -P ${TMP_DIR} --no-proxy --no-check-certificate

echo "task: tar -zxvf ${TMP_DIR}/$kubevirt_package -C ${TMP_DIR}"
tar -zxvf ${TMP_DIR}/$kubevirt_package -C ${TMP_DIR}

for file in $(grep -rnl .image ${TMP_DIR}/);
do echo "task: docker load -i ${file}"
    image=$(echo "${file}" |awk -F'/' '{print $NF}'|awk -F'.' '{print $1}')
    KUBEVIRT_VHOST_VERSION=$(echo "${file}" |awk -F'/' '{print $NF}'|awk -F'.' '{print $2}')

    docker load -i ${file}

    if [ -n "$REGISTRY" ] && [ $BACKEND != "docker" ]; then
        NEW_IMAGE="$REGISTRY$image$IMAGE_TAG"
        echo "Handling image: [${NEW_IMAGE}]"
        echo "--------------------------------------------"
        echo "Tag new docker image"
#        docker tag $OLD_DOCKER_REGISTRY$image:$KUBEVIRT_VHOST_VERSION $NEW_IMAGE
        docker tag $image:$KUBEVIRT_VHOST_VERSION $NEW_IMAGE
        echo "--------------------------------------------"
        echo "task: docker push $NEW_IMAGE"
        docker push $NEW_IMAGE
    fi
done

if [ $? -ne 0 ]; then
    echo "Please set your ENV correctly:"
    echo "1.Append ${REGISTRY}  to your no_proxy setting in /etc/environment"
    echo "2.Append ${REGISTRY}   to your no_proxy setting in /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo "3.Append "\"${REGISTRY}\"" to insecure-registries in /etc/docker/daemon.json"
    echo "4.Run \"systemctl daemon-reload && systemctl restart docker\""
fi

# clean up the environment
rm -rf ${TMP_DIR}