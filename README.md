This script was written to be able to find out the max_sectors_kb
by different hardware.

By the standard, for a ATA drive that supports LBA48, the maximum
command size is 65535 sectors, i.e. 32 MiB - 512, however, it has
turned out that some drives choke if sending down such large
commands, thus this script helps to find the largest command a
drive supports, such that it can be quirked.

Because drives that follow the standard should not be punished by
drives that do not follow the standard.

Usage:

$ sudo ./find-max-sectors.sh /dev/sdX

where sdX is the drive which you have noticed choking on a large
command.
