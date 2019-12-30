# Chrome OS Updater

Update Chrome OS on regular PCs

*Download releases from the [release](https://github.com/MuntashirAkon/chrome_os_updater) section. **DON'T** download the repository as it may be unstable and endup breaking Chrome OS. Use the associated README file for instructions.*

<details>
 <summary>Index</summary>
 
- [Background](#background)
- [Installation and Usage](#installation-and-usage)
  * [Requirements](#requirements)
  * [Installation](#installation)
  * [Usage](#usage)
- [How to revert back if something goes wrong](#how-to-revert-back-if-something-goes-wrong)
- [References](#references)
</details>

## Background

Chrome OS has two _root_ partitions namely **ROOT-A** and **ROOT-B** (partition numbered 3 and 5 respectively). On a regular installation, **ROOT-A** partition is actually the root partition you boot from, and **ROOT-B** partition is only used when you update your Chromebook from *About Chrome OS* page. When you update for the first time, the update is installed at **ROOT-B** partition. So, until you install another update, this partition is the one you boot from. And when another update is installed, it is installed at **ROOT-A**, and again, you boot from **ROOT-A** partition (you get the idea). This is also know as A/B update. I followed similar yet somewhat modified approach to develop `omaha_cros_update.sh` script which can be used to update regular PCs to the latest version of Chrome OS.

There are two types of updates: **delta update** and **full update** (similar to Android updates). Delta update is only available for devices which are updated from a (not-very-old) previous version of Chrome OS as it contains only the changes (delta, in science, always seem to denote change). Full update contains the whole update and can be used by Chrome OS of any version. For some obvious reasons, currently only the full updates can be applied through this script.

Previously on a [separate project](https://github.com/MuntashirAkon/Chrome-OS-Multiboot), I've described how to update Chrome OS from another Linux distro, which was slightly easier to develop than use since installing a Linux distro or even using Live OS can be very annoying only for the purpose of updating Chrome OS. That's why I've been working on this project for some time now. The benefit of this project is that you can update Chrome OS directly from Chrome OS itself (without needing another Linux distro). Moreover, this method of updating Chrome OS is very similar to the native process, thus, the security of your OS (though UEFI itself is a culprit) will be much better provided you're only using Chrome OS (ie. without dual or multibooting).

Consequently, it requires another partition namely **ROOT-B** as well as two optional **KERN-A** and **KERN-B** partitions (the last two partitions are there for kernel storage, but can be empty in our case). In a regular installation, the partitions are already there (remember to increase size of both **ROOT-A** and **ROOT-B** to at least 4 GB), but if you're multibooting with other OSs following my previous instructions, you'll need to create another partition (with `EXT2` partition type and 5 GB size) namely **ROOT-B**. After you apply update from **ROOT-A**, **ROOT-B** will be used as the root partition and vice versa. The benefit of using this approach is that if, for some reason, update doesn't work as expected, you can still be able to use Chrome OS by simply selecting the other partition in the GRUB menu or changing the default partition in the GRUB configuration file.

## Installation and Usage

### Requirements

**There is no requirment for default/regular installation** (ie. wiping the whole drive to install Chrome OS). You will need a configuration file if
- (even one or more of) the partition names (also known as partition labels or `PARTLABEL`) are not standard. The standard partition names (for our purpose) are **KERN-A**, **KERN-B**, **ROOT-A**, **ROOT-B**, **EFI-SYSTEM** (KERN-* partitions are optional). If (even one or more of) the partitions of the drive doesn't have the standard labels, you will need this configuration file.
- you're crazy enough to install two or more Chrome OS in the same drive
- you're not going to use swtpm module even if your kernel supports it (you only need `TPM=false`)

*If the configuration file does not exist, the updater will fall back to the standard labels and will issue a warning.*

<details>
 <summary>Creating the configuration file</summary>

The configuration format is as follows:
```sh
ROOTA='<ROOT-A UUID, lowercase>'
ROOTB='<ROOT-B UUID, lowercase>'
EFI='<EFI-SYSTEM UUID, lowercase>'
TPM=true/false
```
Each value is optional. If a value doesn't exist, default will be used (if available). For swtpm: if you set `TPM=false`, the swtpm installation will be ignored during the update; otherwise, the updater will automatically determine if swtpm is need.

You can get UUID for a disk ID using the following command:
```bash
/sbin/blkid -s UUID -o value /dev/<disk-id>
```
*Notice: **partition UUID** (goes by the name `PARTUUID`) and **UUID** are not the same.*

Save this configuration file as `cros_update.conf` to `/usr/local` (full URI is `/usr/local/cros_update.conf`).

</details>

### Installation

Open crosh shell by pressing `Ctrl` + `Alt` + `T` and the type `shell`. Now copy and paste the command below (don't use `sudo`!):

```sh
curl -Ls https://raw.githubusercontent.com/MuntashirAkon/chrome_os_updater/master/installer.sh | bash
```

or, an easy to remember command:

```sh
curl -Ls https://cutt.ly/cros_updater | bash
```

### Usage

#### Check for updates
```sh
omaha_cros_update.sh --check-only
```

#### Update Chrome OS
```sh
sudo -E omaha_cros_update.sh
```

Required files will be downloaded automatically. An active Internet connection is required throughout the process.

#### Switch update channel

It is possible to switch update channel (however, this is not tested by myself yet). To switch update channel, you need to export `CUSTOM_RELEASE_TRACK` environment variable in the crosh terminal before running the updater. Here's an example:
```sh
export CUSTOM_RELEASE_TRACK=dev-channel
```
`CUSTOM_RELEASE_TRACK` can take one of the following values:
- dev-channel
- canary-channel
- beta-channel
- stable-channel

## How to revert back if something goes wrong

There's always a chance that something will go wrong. In this case, don't panic, but you'll need to use Ubuntu Live (or other Linux distro or even Windows or macOS). Boot into it and follow the steps below.

1. Mount the **EFI-SYSTEM** partition (with `vfat` type and write permission) using *Gparted* (available on Ubuntu Live), *Disks* (comes built-in with Ubuntu), `mount` or other tools. For Windows and macOS users, this partition should already be mounted.
2. If you're using EFI mode, follow steps 3-5. If you're using legacy mode, follow steps 6-8. Otherwise follow all the steps and don't reboot in step 5.
3. Navigate to `efi/boot/grub.cfg` inside the disk and open for editing (on Linux, you'll need root permission).
4. In the 9th line, you'll find something like this:
   ```
   set default=$defaultA
   ```
   Here `$defaultA` might be `$defaultB` for you. If it is set to `$defaultB` make it to `$defaultA` or vice versa. Do the same in the 7th line as well (especially if you've done a clean install).
5. Save it and reboot.
6. Navigate to `syslinux/default.cfg` inside the disk and open for editing (on Linux, you'll need root permission).
7. You'll find a single line like this:
   ```
   DEFAULT chromeos-hd.A
   ```
   Here `chromeos-hd.A` might be `chromeos-hd.B` for you. If it is set to `chromeos-hd.B` make it to `chromeos-hd.A` or vice versa.
8. Save and reboot

This should restore Chrome OS to the previously installed version.

## References
1. https://www.chromium.org/chromium-os/chromiumos-design-docs/disk-format
2. https://chromium.googlesource.com/chromiumos/platform/crosutils/+/refs/heads/master/build_library/disk_layout_v2.json
3. https://chromium.googlesource.com/chromiumos/platform/crosutils/+/refs/heads/master/build_library/create_legacy_bootloader_templates.sh
4. https://chromium.googlesource.com/chromiumos/third_party/grub2/+/refs/heads/master/grub-core/commands/gptpriority.c
5. https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master
6. https://source.android.com/devices/tech/ota/ab/
7. https://www.chromium.org/chromium-os/developer-information-for-chrome-os-devices/cr-48-chrome-notebook-developer-information/how-to-boot-ubuntu-on-a-cr-48
