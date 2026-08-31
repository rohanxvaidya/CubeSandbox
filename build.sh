#!/bin/bash -e
set -x 

IMAGEARCH=${IMAGEARCH:-linux/amd64}
BACKEND=${BACKEND:-docker}
RELEASE=${RELEASE:-:latest}
REGISTRY_PORT=${PORT:-"5000"} # registry port
REGISTRY_IP="10.67.115.219" # default registry
OLD_DOCKER_REGISTRY="${REGISTRY_IP}:${REGISTRY_PORT}/"
REGISTRY=${REGISTRY:-"$REGISTRY_IP:$REGISTRY_PORT/"}
CONFIGURATION_OPTIONS=${CONFIGURATION_OPTIONS:-""}
BENCHMARK_OPTIONS=${BENCHMARK_OPTIONS:-""}

NODE_AFFINITY=${NODE_AFFINITY:-""}  # 0/1 disable/neable node affinity for pod deployment.


DIR="$( cd "$( dirname "$0" )" &> /dev/null && pwd )"

# Arg 1:  the docker image and yaml file build path.
# Arg 2:  ? 
BUILD_PATH=${1:-"${DIR}/"}  # specify the build path.
cd ${DIR}

with_arch () {
    if [[ "$IMAGEARCH" = "linux/amd64" ]]; then
        echo $1
    else
        echo $1-${IMAGEARCH/*\//}
    fi
}


build_yaml () {
    CONFIG_PATH=$1

    for m4file in `find ${CONFIG_PATH}/ -name "*.yaml.m4"`
    do 
        #echo "transfer $m4file"  # m4file is the file name with path.
        m4 -I${CONFIG_PATH} \
        -DPLATFORM=$PLATFORM \
        -DIMAGEARCH=$IMAGEARCH \
        -DNAMESPACE=$NAMESPACE \
        -DIMAGE=$IMAGE \
        -DNODE_AFFINITY=$NODE_AFFINITY \
        -DBENCHMARK_OPTIONS=$BENCHMARK_OPTIONS \
        -DCONFIGURATION_OPTIONS=$CONFIGURATION_OPTIONS \
        $CONFIG_OPTIONS \
        $BENCH_OPTIONS \
        "$m4file" > "${m4file%.m4}"
    done
}


build_options="$(env | cut -f1 -d= | grep -iE '_proxy$' | sed 's/^/--build-arg /'  | tr '\n' ' ')"
build_options="$build_options --build-arg RELEASE=$RELEASE --build-arg BUILDKIT_INLINE_CACHE=1"

if [ "$IMAGEARCH" != "linux/amd64" ]; then
    build_options="$build_options --platform $IMAGEARCH"
fi

if [ -r "$HOME/.netrc" ]; then
    build_options="$build_options --secret id=.netrc,src=$HOME/.netrc"
elif [ -r "/root/.netrc" ]; then
    build_options="$build_options --secret id=.netrc,src=/root/.netrc"
fi

for pattern in '.3.*' '.2.*' '.1.*' ''; do
    for dockerfile in $(find "$BUILD_PATH" -maxdepth 3 -mindepth 1 -name "Dockerfile$pattern" $FIND_OPTIONS -print 2>/dev/null); do

        header_head=$(head -n 2 "$dockerfile" | grep -E '^#+ ' | tail -n 1 | cut -d' ' -f1)
        header_name=$(head -n 2 "$dockerfile" | grep -E '^#+ ' | tail -n 1 | cut -d' ' -f2)

        docker_build_work_path=$(dirname "$dockerfile")
        image=$(with_arch $header_name)
        IMAGE="$REGISTRY$image$RELEASE"
        DOCKER_BUILDKIT=1 \
        docker build $BUILD_OPTIONS $build_options \
        -t $image \
        -t $image$RELEASE $([ -n "$REGISTRY" ] && [ "$header_head" = "#" ] && echo -t $IMAGE) \
        -f "$dockerfile" .
#        ${docker_build_work_path}

        # if REGISTRY is specified, push image to the private registry
        if [ -n "$REGISTRY" ] && [ "$header_head" = "#" ]; then
                docker -D push $IMAGE
        fi

        # apply image name to yaml
        work_path=$(dirname "$dockerfile")
        build_yaml $work_path

    done
done


