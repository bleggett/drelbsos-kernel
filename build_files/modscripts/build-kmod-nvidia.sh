#!/bin/sh

set -oeux pipefail

RELEASE="$(rpm -E '%fedora.%_arch')"
KERNEL_MODULE_TYPE="${1:-kernel-open}"

cd /tmp

### BUILD nvidia

# disable rpmfusion and enable negativo17
sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/rpmfusion-*.repo

curl -L https://negativo17.org/repos/fedora-nvidia.repo \
    -o /etc/yum.repos.d/negativo17-fedora-nvidia.repo

dnf install -y \
    akmod-nvidia*.fc${RELEASE}

# Either successfully build and install the kernel modules, or fail early with debug output
rpm -qa |grep nvidia
KERNEL_VERSION="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
NVIDIA_AKMOD_VERSION="$(basename "$(rpm -q "akmod-nvidia" --queryformat '%{VERSION}-%{RELEASE}')" ".fc${RELEASE%%.*}")"

sed -i "s/^MODULE_VARIANT=.*/MODULE_VARIANT=$KERNEL_MODULE_TYPE/" /etc/nvidia/kernel.conf

akmods --force --kernels "${KERNEL_VERSION}" --kmod "nvidia"

modinfo /usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/nvidia{,-drm,-modeset,-peermem,-uvm}.ko.xz > /dev/null || \
(cat /var/cache/akmods/nvidia/${NVIDIA_AKMOD_VERSION}-for-${KERNEL_VERSION}.failed.log && exit 1)

# View license information
modinfo -l /usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/nvidia{,-drm,-modeset,-peermem,-uvm}.ko.xz

# create a directory for later copying of resulting nvidia specific artifacts
mkdir -p /var/cache/rpms/kmods/nvidia


cat <<EOF > /var/cache/rpms/kmods/nvidia-vars
KERNEL_VERSION=${KERNEL_VERSION}
KERNEL_MODULE_TYPE=${KERNEL_MODULE_TYPE}
RELEASE=${RELEASE}
NVIDIA_AKMOD_VERSION=${NVIDIA_AKMOD_VERSION}
EOF
