# surface-linux-camera-fix

Packages to get the cameras on Microsoft Surface devices working in Linux without using the linux-surface libcamera packages.

This tree builds those packages on the machine. It was verified on a Surface Go 2 (DMI product name `Surface Go 2`, SKU `Surface_Go_2_1927`) running Ubuntu with kernel `7.0.0-34-generic`, libcamera 0.7.0, and PipeWire 1.6.2. The GNOME Camera app shows both picture cameras with left and right in the right places, and with the colours libcamera already produced.

Other Surface models can use the driver package. The left-right mirror is applied only on a Surface Go 2 unless the config file says otherwise.

## Install

Ubuntu or Debian, with the desktop camera stack (PipeWire and libcamera) already installed:

```sh
git clone https://github.com/haleme-chs/surface-linux-camera-fix.git
cd surface-linux-camera-fix
sudo bash install.sh
```

The script installs the build dependencies, builds a DKMS package, builds the PipeWire camera plugin against the installed headers, and restarts the user PipeWire session. Run it again after `git pull`, and after an upgrade of PipeWire. A new kernel rebuilds the DKMS modules on its own, and `/etc/kernel/postinst.d/sign-ipu3-imgu` signs `ipu3-imgu` for that kernel.

If `install.sh` reports that a loaded module is an older build, reboot when you can. The running driver stays in place until then.

## Secure Boot

Ubuntu ships `ipu3-imgu` unsigned. With Secure Boot on, the kernel rejects that module and libcamera lists no cameras. DKMS signs `dw9719` and `ov8865` with the local Machine Owner Key. The install hook signs `ipu3-imgu` with the same key.

On Ubuntu, the first DKMS build creates `/var/lib/shim-signed/mok/` when that key is missing, then asks `mokutil` to enroll `MOK.der`. Choose an enrollment password, reboot, and finish the blue MokManager screen. Run `sudo bash install.sh` again after that reboot so `ipu3-imgu` is signed with the enrolled key.

This repository does not contain a private key or an enrollment password.

## Update

```sh
git pull
sudo bash install.sh
```

`/etc/surface-linux-camera-fix.conf` is a package config file. A later install keeps a local edit.

The plugin sources match PipeWire 1.6.2 (`spa/plugins/libcamera`). A 1.6 update is rebuilt by `install.sh`. A newer major PipeWire may fail to compile. In that case, replace `spa-libcamera/` with the matching `spa/plugins/libcamera` sources and keep the horizontal-mirror block in `libcamera-source.cpp` (`surface_hflip_enabled`, `hflip_nv12`, and the call from `handle_completed_request`).

## What gets installed

- **dw9719-ipu3-dkms 1.4.** `dw9719` binds the focus motor. Ubuntu 7.0 dropped its I2C device id table; this is the upstream driver from commit `d7fe0d53b2a8`, which puts that table back. `ov8865` programs the rear sensor's mode registers when streaming starts, then writes exposure and gain again. The focus-motor link keeps the sensor powered, so the usual resume path never reprograms the chip. Without the mode program the rear camera delivers one frame and then stalls.
- **`/usr/share/libcamera/ipa/ipu3/ov8865.yaml`.** Tuning for the rear sensor. Autofocus is left out. The IPU3 autofocus loop drove the lens and left the picture soft. Exposure stays on the uncalibrated target.
- **`/etc/kernel/postinst.d/sign-ipu3-imgu`.** Signs the image-processor module after a kernel install. It does nothing when no module key exists.
- **A replacement PipeWire `libspa-libcamera.so`.** The distribution file is diverted to `libspa-libcamera.so.distro`. The replacement mirrors finished NV12 frames on a Surface Go 2. A later PipeWire package update writes the new distribution plugin to the `.distro` name and leaves this file in place, so run `install.sh` again after that upgrade.
- **`/etc/surface-linux-camera-fix.conf`.** Controls the mirror.

The front sensor, `ov5693`, stays the distribution module.

## Left and right

`/etc/surface-linux-camera-fix.conf`:

```
hflip=auto
```

`auto` mirrors when `/sys/class/dmi/id/product_name` is exactly `Surface Go 2`. `hflip=yes` mirrors on any machine. `hflip=no` leaves the picture as libcamera produced it. PipeWire reads the file once per process. Restart PipeWire after an edit:

```sh
systemctl --user try-restart pipewire pipewire-pulse wireplumber
```

The mirror runs on the NV12 frame after libcamera has produced the colours. The sensor horizontal-flip control is the wrong tool here: on the front camera it changes the Bayer order and the picture goes magenta, and on the rear camera both flip bits together leave the image where it is. The plugin reports the normal upright transform, so a client does not mirror a second time.

The `cam` utility talks to libcamera directly. Its pictures stay mirrored. The GNOME Camera app goes through PipeWire, which is the path this plugin corrects.

On a Surface Go 2 the same mirror applies to every NV12 camera that plugin serves, including the `ov7251` infrared sensor if an application opens it.

## What this does not change

The rear picture is still soft. Taking autofocus out of the tuning file stopped the lens being driven to a worse position. It does not focus the rear camera. Manual focus on `dw9719` (`focus_absolute`, 0 to 1023) is still available to an application that sets it.

## Leave the camera drivers loaded

Leave `ipu3_cio2`, `ipu3_imgu`, `ov5693`, `ov8865`, and `dw9719` loaded. Unloading that stack hard-locks a Surface Go 2. `install.sh` and `uninstall.sh` never remove a loaded module. Reboot to switch from the running module to the one now on disk.

## Uninstall

```sh
sudo bash uninstall.sh
```

Then reboot. That restores the distribution PipeWire plugin and removes the DKMS package. The config file stays until:

```sh
sudo dpkg --purge dw9719-ipu3-dkms
```

## Licenses

`LICENSE` is the GNU General Public License, version 3, and it covers the install scripts and packaging in this repository.

The kernel modules keep the license in their own headers. `dw9719.c` is GPL-2.0-only. `ov8865.c` is GPL-2.0-or-later. `ov8865.yaml` is CC0-1.0.

`spa-libcamera/` is the PipeWire 1.6.2 libcamera plugin, Copyright Collabora and Wim Taymans, MIT, with the mirror added in `libcamera-source.cpp`. Those files stay under the MIT license named in their headers.

## Layout

```
install.sh                          build, install, and update
uninstall.sh                        restore the distribution plugin and remove the package
etc/surface-linux-camera-fix.conf   hflip=auto
scripts/sign-ipu3-imgu.sh           Secure Boot hook for ipu3-imgu
dkms/dw9719-ipu3/                   dw9719, ov8865, tuning file, DKMS packaging
spa-libcamera/                      PipeWire 1.6.2 plugin plus the NV12 mirror
```
