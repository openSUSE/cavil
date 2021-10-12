# Defines the tag for OBS and build script builds:
#!BuildTag: opensuse/golang:1.16
#!BuildTag: opensuse/golang:%%PKG_VERSION%%
#!BuildTag: opensuse/golang:%%PKG_VERSION%%.%RELEASE%
#
# SPDX-License-Identifier: BSD-3-Clause
#

ARG BASE=opensuse/tumbleweed
FROM $BASE

# labelprefix=org.opensuse.golang
PREFIXEDLABEL org.opencontainers.image.description="Whatever"

ENV GOLANG_VERSION %%PKG_VERSION%%
ENV GOPATH /go
ENV PATH $GOPATH/bin:$PATH

# Work around https://github.com/openSUSE/obs-build/issues/487
ARG RELEASE_PACKAGE=openSUSE-release-appliance-docker
RUN zypper install -y --no-recommends $RELEASE_PACKAGE go1.16 git-core && \
    zypper clean && \
    mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

WORKDIR $GOPATH
CMD [ "/bin/bash" ]
