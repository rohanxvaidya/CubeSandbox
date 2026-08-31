#! /bin/bash
#
# The kubeivrt customized image were built by developer, and need to be stored in artifactory website, and it's free for internal download without any credential.
# with this script user can pull the image from registry which contains the customized kubevirt images, then save to image and package them
# after that upload the tarball package to atifactory.

KUBEVIRT_VHOST_VERSION=${KUBEVIRT_VHOST_VERSION:-"TEST_V4"} # The customized kubevirt release version
USER_NAME=${1:-"mzhang2"}
TOKEN=${2:-"AP9tpjsYVoP2EKPWGTMUVtzUDAA"}
REGISTRY=${REGISTRY:-"10.67.115.219"}
PORT=${PORT:-"5000"}
TMP_DIR=${TMP_DIR:-"/tmp/docker_image_tar"}
REGISTRY_PORT=${PORT:-"5000"} # registry port
REGISTRY_IP="10.67.115.219" # default registry
OLD_DOCKER_REGISTRY="${REGISTRY_IP}:${REGISTRY_PORT}/"
kubevirt_package="kubevirt-virtIO-${KUBEVIRT_VHOST_VERSION}.tar.gz"
kubevirt_package_r="kubevirt-virtIO-${KUBEVIRT_VHOST_VERSION}_R"
kubevirt_package_r_tgz="${kubevirt_package_r}.tar.gz"
uploadUri=${uploadUri:-"https://af01p-igk.devtools.intel.com/artifactory/platform_hero-igk-local/hero_features_assets/Edge/Storage/kubevirt/${kubevirt_package}"}
uploadUri_r=${uploadUri_r:-"https://af01p-igk.devtools.intel.com/artifactory/platform_hero-igk-local/hero_features_assets/Edge/Storage/kubevirt/${kubevirt_package_r_tgz}"}

KUBEVIRT_IMAGES_LIST=(
    example-hook-sidecar
    alpine-container-disk-demo
    microlivecd-container-disk-demo
    fedora-realtime-container-disk
    subresource-access-test
    winrmcli
    vm-killer
    cirros-custom-container-disk-demo
    nfs-server
    disks-images-provider
    cirros-container-disk-demo
    example-cloudinit-hook-sidecar
    virtio-container-disk
    alpine-ext-kernel-boot-demo
    fedora-with-test-tooling-container-disk
    virt-operator
    virt-api
    virt-controller
    virt-handler
    virt-launcher
    conformance
    libguestfs-tools
    )

KUBEVIRT_IMAGES_LIST_R=(
    example-hook-sidecar
    disks-images-provider
    virtio-container-disk
    virt-operator
    virt-api
    virt-controller
    virt-handler
    virt-launcher
    )

mkdir -p ${TMP_DIR}
rm -rf ${TMP_DIR}/*
docker --version
if [ $? -ne 0 ]; then
    echo "Please install docker-ce first."
    # clean up the environment
    rm -rf ${TMP_DIR}
    exit 1
fi
#kubevirt_package="kubevirt-virtIO-${KUBEVIRT_VHOST_VERSION}.tar.gz"
echo  "kubevirt_package is: ${kubevirt_package}"

for IMAGE_NAME in ${KUBEVIRT_IMAGES_LIST[@]};
do
	echo "task: docker pull $REGISTRY:$PORT/$IMAGE_NAME:$KUBEVIRT_VHOST_VERSION"
    docker pull $REGISTRY:$PORT/$IMAGE_NAME:$KUBEVIRT_VHOST_VERSION
    echo "task: docker tag $REGISTRY:$PORT/$IMAGE_NAME:$KUBEVIRT_VHOST_VERSION $IMAGE_NAME:$KUBEVIRT_VHOST_VERSION"
    docker tag $REGISTRY:$PORT/$IMAGE_NAME:$KUBEVIRT_VHOST_VERSION $IMAGE_NAME:$KUBEVIRT_VHOST_VERSION
    echo "task: docker image save to ${TMP_DIR}"
    docker save -o ${TMP_DIR}/${IMAGE_NAME}.${KUBEVIRT_VHOST_VERSION}.image $IMAGE_NAME:$KUBEVIRT_VHOST_VERSION
done

if [ $? -ne 0 ]; then
    echo "Please set your ENV correctly:"
    echo "1.Append ${REGISTRY}  to your no_proxy setting in /etc/environment"
    echo "2.Append ${REGISTRY}   to your no_proxy setting in /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo "3.Append "\"${REGISTRY}:${PORT}\"" to insecure-registries in /etc/docker/daemon.json"
    echo "4.Run \"systemctl daemon-reload && systemctl restart docker\""
    # clean up the environment
    rm -rf ${TMP_DIR}
    exit 1
fi

echo "task: cd ${TMP_DIR} && tar -zcvf ${kubevirt_package} *.image"
cd ${TMP_DIR} && tar -zcvf ${kubevirt_package} *.image
echo "------------------------------------------------------"
echo "The local file[${kubevirt_package}] md5sum is $(md5sum ${TMP_DIR}/${kubevirt_package})"
echo "------------------------------------------------------"
#curl -u${USER_NAME}:${TOKEN} -T ${TMP_DIR}/${kubevirt_package}  "https://af01p-igk.devtools.intel.com/artifactory/platform_hero-igk-local/hero_features_assets/Edge/Storage/kubevirt/${kubevirt_package}" --noproxy "*"
curl -u${USER_NAME}:${TOKEN} -T ${TMP_DIR}/${kubevirt_package}  ${uploadUri} --noproxy "*"

echo "For the reduced kubevirt image package"
cd ${TMP_DIR} 
for IMAGE_R_NAME in ${KUBEVIRT_IMAGES_LIST_R[@]};
do
    tar -rvf ${kubevirt_package_r}.tar ${IMAGE_R_NAME}.${KUBEVIRT_VHOST_VERSION}.image 
done

echo "Package to ${kubevirt_package_r_tgz}"
gzip ${kubevirt_package_r}.tar  # ${kubevirt_package_r}.tar.gz

if [ -e ${kubevirt_package_r_tgz} ]; then
    echo "------------------------------------------------------"
    echo "The local file[${kubevirt_package_r_tgz}] md5sum is $(md5sum ${TMP_DIR}/${kubevirt_package_r_tgz})"
    echo "------------------------------------------------------"

    curl -u${USER_NAME}:${TOKEN} -T ${TMP_DIR}/${kubevirt_package_r_tgz}  ${uploadUri_r} --noproxy "*"
fi

# clean up the environment
rm -rf ${TMP_DIR}

