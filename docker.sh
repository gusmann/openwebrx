#!/usr/bin/env bash
set -euo pipefail

ARCH=$(uname -m)
IMAGES="openwebrx-rtlsdr openwebrx-sdrplay openwebrx-hackrf openwebrx-airspy openwebrx-afedri openwebrx-rtlsdr-soapy openwebrx-plutosdr openwebrx-limesdr openwebrx-soapyremote openwebrx-perseus openwebrx-fcdpp openwebrx-radioberry openwebrx-uhd openwebrx-rtltcp openwebrx-runds openwebrx-hpsdr openwebrx-bladerf openwebrx-full openwebrx"
ALL_ARCHS="x86_64 armv7l aarch64"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-docker.io}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-jketterl}"
TAG=${TAG:-"latest"}
ARCHTAG="${TAG}-${ARCH}"

usage () {
  echo "Usage: ${0} [command] [image]"
  echo "Available commands:"
  echo "  help       Show this usage information"
  echo "  build      Build docker image(s). Specify an image name or 'all' for all images."
  echo "  push       Push docker image(s) to the docker hub. Specify an image name or 'all' for all images."
  echo "  manifest   Compile the docker hub manifest (combines arm and x86 tags into one)"
  echo "  tag        Tag a release"
  echo ""
  echo "Available images: ${IMAGES}"
}

build () {
  local target_image="${1:-}"
  if [ -z "$target_image" ]; then
    echo "Error: Please specify an image name or 'all'"
    echo "Available images: ${IMAGES}"
    return 1
  elif [ "$target_image" != "all" ] && [[ ! " ${IMAGES} " =~ " ${target_image} " ]]; then
    echo "Error: Image '${target_image}' not found in available images"
    echo "Available images: ${IMAGES}"
    return 1
  fi
  for ARCHTAG in ${ALL_ARCHS}; do
    # build the base images
    docker build --pull -t openwebrx-base:${TAG}-${ARCHTAG} -f docker/Dockerfiles/Dockerfile-base .
    docker build --build-arg ARCHTAG=${TAG}-${ARCHTAG} -t openwebrx-soapysdr-base:${TAG}-${ARCHTAG} -f docker/Dockerfiles/Dockerfile-soapysdr .

    local build_images="${target_image}"
    if [ "$target_image" = "all" ]; then
      build_images="${IMAGES}"
    fi

    for image in ${build_images}; do
      i=${image:10}
      # "openwebrx" is a special image that gets tag-aliased later on
      if [[ ! -z "${i}" ]] ; then
        docker build --build-arg ARCHTAG=${TAG}-$ARCHTAG -t ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TAG}-${ARCHTAG} -f docker/Dockerfiles/Dockerfile-${i} .
        docker push ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TAG}-${ARCHTAG}
      fi
    done

    # tag openwebrx alias image
    if [ "$target_image" = "all" ] || [ "$target_image" = "openwebrx-full" ]; then
      docker tag ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/openwebrx-full:${TAG}-${ARCHTAG} ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/openwebrx:${TAG}-${ARCHTAG}
      docker push ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/openwebrx:${TAG}-${ARCHTAG}
    fi
  done
}

push () {
  local target_image="${1:-}"
  if [ -z "$target_image" ]; then
    echo "Error: Please specify an image name or 'all'"
    echo "Available images: ${IMAGES}"
    return 1
  elif [ "$target_image" != "all" ] && [[ ! " ${IMAGES} " =~ " ${target_image} " ]]; then
    echo "Error: Image '${target_image}' not found in available images"
    echo "Available images: ${IMAGES}"
    return 1
  fi

  local push_images="${target_image}"
  if [ "$target_image" = "all" ]; then
    push_images="${IMAGES}"
  fi

  for image in ${push_images}; do
    docker push ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TAG}-${ARCHTAG}
  done
}

manifest () {
  for image in ${IMAGES}; do
    # there's no docker manifest rm command, and the create --amend does not work, so we have to clean up manually
    rm -rf "${HOME}/.docker/manifests/${IMAGE_REGISTRY}_${IMAGE_REPOSITORY/\//_}_${image}-${TAG}"
    IMAGE_LIST=""
    for a in ${ALL_ARCHS}; do
      IMAGE_LIST="${IMAGE_LIST} ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TAG}-${a}"
      docker pull ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TAG}-${a}
    done
    docker manifest create ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TAG} ${IMAGE_LIST}
    docker manifest push --purge ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TAG}
  done
}

tag () {
  if [[ -x ${1:-} || -z ${2:-} ]] ; then
    echo "Usage: ${0} tag [SRC_TAG] [TARGET_TAG]"
    return
  fi

  local SRC_TAG=${1}
  local TARGET_TAG=${2}

  for image in ${IMAGES}; do
    # there's no docker manifest rm command, and the create --amend does not work, so we have to clean up manually
    rm -rf "${HOME}/.docker/manifests/${IMAGE_REGISTRY}_${IMAGE_REPOSITORY/\//_}_${image}-${TARGET_TAG}"
    IMAGE_LIST=""
    for a in ${ALL_ARCHS}; do
      docker pull ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${SRC_TAG}-${a}
      docker tag ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${SRC_TAG}-${a} ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TARGET_TAG}-${a}
      docker push ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TARGET_TAG}-${a}
      IMAGE_LIST="${IMAGE_LIST} ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TARGET_TAG}-${a}"
    done
    docker manifest create ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TARGET_TAG} ${IMAGE_LIST}
    docker manifest push --purge ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TARGET_TAG}
    docker pull ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${image}:${TARGET_TAG}
  done
}

case ${1:-} in
  build)
    build ${@:2}
    ;;
  push)
    push ${@:2}
    ;;
  manifest)
    manifest
    ;;
  tag)
    tag ${@:2}
    ;;
  *)
    usage
    ;;
esac