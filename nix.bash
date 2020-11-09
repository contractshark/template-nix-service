#!/usr/bin/env bash
# version 0.2.0
# SPDX-License-Identifier: ISC

set -e

# A NIX Bash psudo-script
# ["(%)"] = fingerprint 
# ["{%}"] == fingerprint exec 
# [$1] [$2] == build tooling , e.g. poetry or gradle, etc 
# this is not per se bash script rather just an annotated working script without bashisms 
# replace the variables above with your relevent commands 
# Two Services: PRODUCTION and TESTING 

CONTAINER_NAME=$ORG-env.nix

TAG=${1:-master}
REPOSITORY=${2:-local}
PRODUCTION=${PRODUCTION:-1}
MEMORY_PROTECT=${MEMORY_PROTECT:-1}

if [ "$REPOSITORY" = "local" ]; then
  REPOSITORY=file:///local/
else
  REPOSITORY=https://github.com/$ORG/$REPOSITORY.git
fi

wget -nc -P ci/ http://dl-cdn.alpinelinux.org/alpine/v3.12/releases/x86_64/alpine-minirootfs-3.12.0-x86_64.tar.gz
docker build -t "$CONTAINER_NAME" ci/

USER=$(find . type -f | awk '{ print $3 }')
GROUP=$(find . type -f | awk '{ print $4 }')

mkdir -p "$(pwd)/build/core"
mkdir -p "$(pwd)/build/$SERVICE"

# an example build 
# [$1] [$2] == $BUILDTOOL

for SERVICE in 0 1; do

  DIRSUFFIX=${$SERVICE/1/-production}
  DIRSUFFIX=${DIRSUFFIX/0/}

  docker run -it --rm \
    -v "$(pwd)":/local \
    -v "$(pwd)"/build/core"${DIRSUFFIX}":/build:z \
    --env $SERVICE="$SERVICE" \
    --env PRODUCTION="$PRODUCTION" \
    "$CONTAINER_NAME" \
    /nix/var/nix/profiles/default/bin/nix-shell --run "\
      cd /tmp && \
      git clone $REPOSITORY $ORG && \
      cd $ORG/core && \
      ln -s /build build &&
      git checkout $TAG && \
      git submodule update --init --recursive && \
      [$1] && \
      [$2] && \
      {{ some command }} \
          -o {{ WORKINGDIR }}/{{ BUILD }} \
          {{ . }} && \
      chown -R $USER:$GROUP /build"

done

# build testing

for SERVICE in 0 1; do

  DIRSUFFIX=${$SERVICE/1/-production}
  DIRSUFFIX=${DIRSUFFIX/0/}

  docker run -it --rm \
    -v "$(pwd)":/local \
    -v "$(pwd)"/build/testing"${DIRSUFFIX}":/build:z \
    --env $SERVICE="$$SERVICE" \
    --env MEMORY_PROTECT="$MEMORY_PROTECT" \
    "$CONTAINER_NAME" \
    /nix/var/nix/profiles/default/bin/nix-shell --run "\
      cd /tmp && \
      git clone $REPOSITORY $ORG && \
      cd $ORG/testing && \
      ln -s /build build &&
      git checkout $TAG && \
      git submodule update --init --recursive && '\
      $BUILDTOOL install && '\
      $BUILDTOOL run script/cibuild && '\
      mkdir -p build/firmware && '\
      cp {{ exec.BIN }} ["'(%)"] && '\
      cp ["(%)"] ["{%}"] && \
      $BUILDTOOL run ...["$BUILDTOOL_FINALIZE"] \
          -o ["(%)"].fingerprint \
          ["{%}"] && \
      chown -R "$USER:$GROUP" /build

done

# all built, show fingerprints

echo "Fingerprints:"
for VARIANT in core testing; do
  for SERVICE in 0 1; do

    DIRSUFFIX=${$SERVICE/1/-testing}
    DIRSUFFIX=${DIRSUFFIX/0/}

    FWPATH="build/${VARIANT}${DIRSUFFIX}/[%]"
    FINGERPRINT=$(tr -d "\n" < "$FWPATH.fingerprint")
    echo -ne "$FINGERPRINT" "$FWPATH"
  
     done
done
