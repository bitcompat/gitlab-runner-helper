# renovate: datasource=gitlab-releases depName=gitlab-org/gitlab-runner extractVersion=^v(?<version>\d+\.\d+.\d+)
ARG VERSION=16.1.0

# syntax=docker/dockerfile:1.4
FROM golang:1.20-bullseye AS golang-builder

COPY --link --from=ghcr.io/bitcompat/dumb-init:1.2.5-bullseye-r2 /opt/bitnami/ /opt/bitnami/
COPY --link --from=ghcr.io/bitcompat/nss-wrapper:1.1.15-bullseye-r3 /opt/bitnami/ /opt/bitnami/

ARG PACKAGE=gitlab-runner-helper
ARG TARGET_DIR=gitlab-runner-helper
ARG VERSION
ARG REF=v${VERSION}
ARG CGO_ENABLED=0

RUN mkdir -p /opt/bitnami
COPY prebuildfs /

RUN go install github.com/mitchellh/gox@latest
RUN --mount=type=cache,target=/root/.cache/go-build <<EOT /bin/bash
    set -ex

    rm -rf ${PACKAGE} || true
    mkdir -p ${PACKAGE}
    git clone -b "${REF}" https://gitlab.com/gitlab-org/gitlab-runner.git ${PACKAGE}

    pushd ${PACKAGE}
    make helper-bin-host GO_ARCH_aarch64=linux/arm64

    mkdir -p /opt/bitnami/${TARGET_DIR}/licenses
    mkdir -p /opt/bitnami/${TARGET_DIR}/bin
    cp -f LICENSE /opt/bitnami/${TARGET_DIR}/licenses/gitlab-runner-${VERSION}.txt
    cp -f out/binaries/gitlab-runner-helper/gitlab-runner-helper.* /opt/bitnami/${TARGET_DIR}/bin/${PACKAGE}
    popd

    rm -rf ${PACKAGE}

    echo "#!/bin/bash
umask 0000
exec /bin/bash
" > /opt/bitnami/${PACKAGE}/bin/gitlab-runner-build
    chmod 755 /opt/bitnami/${PACKAGE}/bin/gitlab-runner-build

    strip --strip-all /opt/bitnami/${TARGET_DIR}/bin/* || true
    strip --strip-all /opt/bitnami/common/bin/* || true
EOT

COPY rootfs /

FROM bitnami/minideb:bullseye as stage-0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --link --from=golang-builder /opt/bitnami /opt/bitnami

RUN install_packages ca-certificates git git-lfs openssh-client procps \
    && mkdir /home/gitlab-runner \
    && chmod -R g+rwX /home/gitlab-runner \
    && ln -s /opt/bitnami/common/bin/dumb-init /usr/bin/dumb-init \
    && ln -s /opt/bitnami/gitlab-runner-helper/bin/gitlab-runner-helper /usr/bin/gitlab-runner-helper \
    && ln -s /opt/bitnami/scripts/gitlab-runner-helper/entrypoint.sh /entrypoint

ARG VERSION
ENV APP_VERSION=$VERSION \
    BITNAMI_APP_NAME="gitlab-runner-helper" \
    PATH="/opt/bitnami/common/bin:/opt/bitnami/gitlab-runner-helper/bin:$PATH" \
    HOME="/" \
    OS_ARCH="${TARGETARCH:-amd64}" \
    OS_FLAVOUR="debian-11" \
    OS_NAME="linux"

LABEL org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.ref.name="15.11.0-debian-11-r0" \
      org.opencontainers.image.source="https://github.com/bitcompat/gitlab-runner-helper" \
      org.opencontainers.image.title="gitlab-runner-helper" \
      org.opencontainers.image.version="15.11.0"

USER 1001
ENTRYPOINT [ "/usr/bin/dumb-init", "/opt/bitnami/scripts/gitlab-runner-helper/entrypoint.sh" ]
CMD [ "sh" ]

