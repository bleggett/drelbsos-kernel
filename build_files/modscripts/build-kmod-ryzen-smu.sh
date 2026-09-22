#!/bin/sh

set -oeux pipefail

ARCH="$(rpm -E '%_arch')"
KERNEL="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
RELEASE="$(rpm -E '%fedora')"

curl -LsSf -o /etc/yum.repos.d/terra.repo "https://raw.githubusercontent.com/terrapkg/packages/f${RELEASE}/anda/terra/release/terra.repo"
curl -LsSf -o /etc/pki/rpm-gpg/RPM-GPG-KEY-terra${RELEASE} \
    "https://raw.githubusercontent.com/terrapkg/packages/f${RELEASE}/anda/terra/gpg-keys/RPM-GPG-KEY-terra${RELEASE}"
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-terra${RELEASE}

### BUILD ryzen-smu (succeed or fail-fast with debug output)
dnf install -y \
    akmod-ryzen_smu-*.fc${RELEASE}.${ARCH}
akmods --force --kernels "${KERNEL}" --kmod ryzen_smu
modinfo /usr/lib/modules/${KERNEL}/extra/ryzen_smu/ryzen_smu.ko.xz > /dev/null \
|| (find /var/cache/akmods/ryzen_smu/ -name \*.log -print -exec cat {} \; && exit 1)

dnf download --destdir /var/cache/rpms/kmods \
    ryzen_smu \
    ryzen_smu-akmod-modules

rm -f /etc/yum.repos.d/terra.repo
