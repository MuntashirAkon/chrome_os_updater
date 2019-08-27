# Chrome OS Updater

Update Chrome OS on regular PCs

*Download releases from the [release](https://github.com/MuntashirAkon/chrome_os_updater) section. Don't download the repository as it may be unstable and endup breaking Chrome OS.*

<details>
 <summary>Index</summary>
 
- [Guide](#guide)
  * [Background](#background)
  * [How to use](#how-to-use)
  * [How to revert back if something goes wrong](#how-to-revert-back-if-something-goes-wrong)
- [References](#references)
</details>

## Guide

### Background

Chrome OS has two root partitions namely **ROOT-A** and **ROOT-B** (partition no. 3 and 5 respectively). **ROOT-A** partition is actually the partition you're booting from (on regular installation) and **ROOT-B** partition is only used when you update your Chromebook from *About Chrome OS* page. It applies the update to **ROOT-B** and later the update is applied to **ROOT-A**, and finally, you boot from **ROOT-A** partition. I followed the similar yet somewhat modified approach to develop the `cros_update.sh` script which can be used to update regular PCs to the latest version of Chrome OS.

The update is of two types: **delta update** and **full update** (similar to Android updates). Delta update is only available for devices which are updated from a previous (but not very old) version of Chrome OS as it contains only the changes (delta, in science, always seem to denote change). Full update constains the whole update and can be used by Chrome OS of any version. Sadly, unlike Android updates, these sort of updates can only be applied by the Chromebook users as the Chrome OS installed on regular PCs are highly modified. The only way (that I'm currently of) is using the recovery files to update regular PCs to the latest version of Chrome OS.

Previously on a separate project, I've described how to update Chrome OS from another Linux distro, which was slightly easier to develop and use. However, installing a Linux distro or even using Ubuntu Live can be very annoying only for the purpose of updating Chrome OS. That's why I've been working on this project for some time now. The benefit of this project is you can update Chrome OS directly from Chrome OS itself (without needing another Linux distro).

However, it requires another partition namely **ROOT-B**. In a regular installation, the partition is already there, but if you're multibooting with other OSes, you'll need to create another partition (with `EXT2` partition type and 5 GB size) namely **ROOT-B**. After you apply update from **ROOT-A**, **ROOT-B** will be used as the root partition and vice versa (notice that this doesn't follow the Chrome OS' original convention). The benefit of using this approach is that, if for some reason, update doesn't work as expected, you can still be able to use Chrome OS by simply changing the partition UUID in the GRUB configuration file.

### How to use

`cros_update.sh` requires a configuration file (namely `cros_update.conf`) to be located at `/usr/local` (full URI is `/usr/local/cros_update.conf`). This config file helps the script figuring out the partitions where update should take place. The format as follows:
```sh
ROOTA='<ROOT-A UUID, lowercase>'
ROOTB='<ROOT-B UUID, lowercase>'
EFI='<EFI-SYSTEM UUID, lowercase>'
TPM=true/false
```

You can get UUID for a disk ID using the following command:
```bash
/sbin/blkid -s UUID -o value /dev/<disk-id>
```
*Note that **partition UUID** and **UUID** are not the same.*

After that you can simply run: (condering that you'll be saving `cros_update.sh` at `~/Downloads` folder`)
```
sudo bash ~/Downloads/cros_update.sh
```
to update your Chrome OS. The script will download the necessary file automatically.

### How to revert back if something goes wrong

There's always a chance that something will go wrog. In this case, don't panic, but you'll need to use Ubuntu Live (or other Linux distro or even Windows or macOS). Boot into it and follow the steps bellow.

- Find the disk id of **ROOT-A** and **ROOT-B** partitions
- Now find the partition UUID of the partitions, like this (search online for appropriate command if you're using Windows or macOS)
```sh
/sbin/blkid -s PARTUUID -o value /dev/<disk-id>
```
- Mount the **EFI-SYSTEM** partition using Disks or other tools or command line (for Windows and macOS users, this should already be mounted)
- Nevigate to `efi/boot/grub.cfg` and open for editing (on Linux, you'll need root permissions)
- Find the existing PARTUUID (look at the first entry, i.e. **local image A**) and match it with the UUIDs you've extracted earlier
- Replace the PARTUUID which is *not* present there
- Reboot
- This should restore Chrome OS to the previous version

## References
1. https://www.chromium.org/chromium-os/chromiumos-design-docs/disk-format
