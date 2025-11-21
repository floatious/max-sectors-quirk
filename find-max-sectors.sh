#!/bin/bash

[[ -d /sys/kernel/mm/transparent_hugepage ]] || {
	echo please enable transparent hugepages in your kernel config
	exit 1
}

[[ $(type -P fio) ]] || {
	echo please install fio
	exit 1
}

[[ $(type -P lsblk) ]] || {
	echo please install lsblk
	exit 1
}

[[ $(type -P lspci) ]] || {
	echo please install lspci
	exit 1
}

if [ -z "$1" ]; then
	echo please specify a block device, e.g. /dev/sda
	exit 1
fi

bdev=$(realpath "$1")
if [ ! -b "${bdev}" ]; then
	echo "${bdev} is not a block device file"
	exit 1
fi

echo Drive model:
echo $(lsblk -n -o MODEL,REV "$bdev" | tr -d '\n')
echo

echo Drive firmware:
echo $(lsblk -n -o REV "$bdev" | tr -d '\n')
echo

bname=$(basename "$bdev")
diskpath=$(ls -l /dev/disk/by-path | grep "$bname"$)
pcidev=$(echo "$diskpath" | sed -nE 's/.*pci-([[:xdigit:]]+:[[:xdigit:]]+:[[:xdigit:]]+\.[[:xdigit:]]+)-.*/\1/p;q')
if [ -n "$pcidev" ]; then
	hba=$(lspci -nns "$pcidev")
else
	hba="Could not detect PCI device"
fi

echo SATA / AHCI controller:
echo "$hba"
echo

echo Drive values before running the test:
grep . /sys/block/"$bname"/queue/{max_hw_sectors_kb,max_sectors_kb,read_ahead_kb}
initial_max_sectors_kb=$(cat /sys/block/"$bname"/queue/max_sectors_kb)
max_hw_sectors_kb=$(cat /sys/block/"$bname"/queue/max_hw_sectors_kb)
echo

declare -a sizes=(128 1024 2048 3072 4095 4096)

function enable_hugepages()
{
	local hugetlbfs="/dev/hugepages"

	if [ ! -e "${hugetlbfs}" ]; then
		echo "${hugetlbfs} does not exist: create it"
		echo "E.g. mkdir ${hugetlbfs}"
		exit 1
	fi

	hugemount=$(mount | grep -c "${hugetlbfs}")
	if [ "${hugemount}" != "1" ]; then
		echo "${hugetlbfs} is not mounted: mount it"
		echo "E.g. mount -t hugetlbfs -o rw,nosuid,nodev,relatime,pagesize=2M nodev ${hugetlbfs}"
		exit 1
	fi

	echo "1" > /proc/sys/vm/drop_caches
	echo "2048" > /proc/sys/vm/nr_hugepages
	echo "always" > /sys/kernel/mm/transparent_hugepage/enabled
	echo "always" > /sys/kernel/mm/transparent_hugepage/hugepages-2048kB/enabled
	echo "always" > /sys/kernel/mm/transparent_hugepage/hugepages-2048kB/shmem_enabled
}

function disable_hugepages()
{
	echo "madvise" > /sys/kernel/mm/transparent_hugepage/enabled
	echo "inherit" > /sys/kernel/mm/transparent_hugepage/hugepages-2048kB/enabled
	echo "inherit" > /sys/kernel/mm/transparent_hugepage/hugepages-2048kB/shmem_enabled
	echo 0 > /proc/sys/vm/nr_hugepages
}

enable_hugepages || exit 1

fiocmd="fio"
fiocmd+=" --name=read"
fiocmd+=" --alloc-size=524288"
fiocmd+=" --ioengine=libaio"
fiocmd+=" --iodepth=32"
fiocmd+=" --direct=1"
fiocmd+=" --rw=read"
fiocmd+=" --runtime=10"
fiocmd+=" --filename=$bdev"
fiocmd+=" --iomem=mmaphuge:$(mktemp -u -p /dev/hugepages)"
fiocmd+=" --iomem_align=2M"

for s in "${sizes[@]}"; do
	if [ "$s" -gt "$max_hw_sectors_kb" ]; then
		break
	fi
	echo Running test with max_sectors "$s" KiB
	echo "$s" > "/sys/block/${bname}/queue/max_sectors_kb"
	cmd="$fiocmd --bs=${s}k"
	eval "$cmd" > /dev/null
	if [ $? -eq 0 ]; then
		echo Test: PASS
	else
		echo Test: FAILURE
		break
	fi
	echo
done

echo "$initial_max_sectors_kb" > "/sys/block/${bname}/queue/max_sectors_kb"

disable_hugepages
