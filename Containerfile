ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"
ARG NVIDIA_DRIVER_VERSION
ARG FEDORA_KERNEL_SHA

FROM fedora:${FEDORA_MAJOR_VERSION} as fedora-builder

ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"
ARG NVIDIA_DRIVER_VERSION
ARG FEDORA_KERNEL_SHA

RUN dnf install -y fedpkg fedora-packager rpmdevtools ncurses-devel pesign \
    asciidoc audit-libs-devel bc bindgen binutils-devel bison clang dwarves \
    elfutils-devel flex fuse-devel gcc gcc-c++ gettext glibc-static hostname \
    java-devel kernel-rpm-macros libbabeltrace-devel libbpf-devel ccache \
    libcap-devel libcap-ng-devel libmnl-devel libnl3-devel libtraceevent-devel \
    libtracefs-devel lld llvm-devel lvm2 m4 make net-tools newt-devel \
    numactl-devel openssl openssl-devel pciutils-devel perl perl-devel \
    perl-generators python3-devel python3-docutils rsync rust rust-src \
    systemd-boot-unsigned systemd-ukify which xmlto xz-devel zlib-devel \
    python3-requests hmaccalc dracut tpm2-tools rustfmt clippy && dnf clean all

ENV PATH="/usr/lib64/ccache/:$PATH"

FROM fedora-builder as kernel-builder

ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"
ARG NVIDIA_DRIVER_VERSION

WORKDIR /workspace

COPY drelbsos-kconfig-overrides .

RUN fedpkg co -a kernel -b f"${FEDORA_MAJOR_VERSION}"
WORKDIR /workspace/kernel
RUN [ -z "${FEDORA_KERNEL_SHA}" ] || git checkout "${FEDORA_KERNEL_SHA}"

RUN sed -i 's/^# define buildid \.local$/%define buildid .drelbsos/' kernel.spec
RUN cat ../drelbsos-kconfig-overrides >> kernel-local
RUN find . -type f -name "kernel*.config" -not -name "kernel-x86_64*.config" -exec rm {} \;
RUN sed -i -E '/(aarch64|riscv64|s390|ppc64le).*\.config/d' kernel.spec

RUN fedpkg --name kernel --namespace rpms --release "f${FEDORA_MAJOR_VERSION}" \
    local --arch x86_64 --with baseonly \
    --builddir build --buildrootdir buildroot
RUN mkdir -p debuginfo && mv x86_64/kernel-debuginfo-*.rpm debuginfo/
RUN mkdir -p /tmp/rpms
RUN mv x86_64/kernel-*.rpm /tmp/rpms
RUN ls -lah /tmp/rpms

FROM kernel-builder as module-builder

ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"
ARG NVIDIA_DRIVER_VERSION

WORKDIR /workspace

COPY build_files/modscripts /tmp/
COPY build_files/shared /tmp/
# COPY certs /tmp/certs

# files for akmods
ADD https://copr.fedorainfracloud.org/coprs/ublue-os/akmods/repo/fedora-${FEDORA_MAJOR_VERSION}/ublue-os-akmods-fedora-${FEDORA_MAJOR_VERSION}.repo \
    /tmp/ublue-os-akmods-addons/rpmbuild/SOURCES/_copr_ublue-os-akmods.repo
ADD https://negativo17.org/repos/fedora-multimedia.repo \
    /tmp/ublue-os-akmods-addons/rpmbuild/SOURCES/negativo17-fedora-multimedia.repo

COPY --from=kernel-builder /tmp/rpms /tmp/kernel_cache

ENV NVIDIA_DRIVER_VERSION=${NVIDIA_DRIVER_VERSION}

RUN --mount=type=cache,dst=/var/cache/dnf \
    ls -sh /tmp/kernel_cache; \
    /tmp/build-prep.sh && \
    /tmp/build-kmod-gcadapter_oc.sh && \
    /tmp/build-kmod-ryzen-smu.sh && \
    /tmp/build-kmod-vhba.sh && \
    /tmp/build-kmod-xone.sh && \
    /tmp/build-kmod-nvidia.sh && \
    /tmp/build-kmod-openrazer.sh && \
    # /tmp/build-kmod-v4l2loopback.sh && \
    # /tmp/dual-sign.sh && \
    /tmp/build-post.sh


FROM scratch

COPY --from=kernel-builder /tmp/rpms /kernel-rpms
COPY --from=module-builder /var/cache/rpms /kmod-rpms
