# CentOS Stream 10 Alternative Image KIWI descriptions

This contains the KIWI descriptions for building Alternative Images for CentOS Stream 10.

## Image variants

* Cloud (image type: `oem`, image profiles: `OpenStack`/`AWSEC2`/`Azure`/`GCE`)
* Workstation GNOME (image type: `iso`, image profiles: `GNOME-Live`)
* Workstation KDE (image type: `iso`, image profiles: `KDE-Live`)
* Text Only Live image (image type: `iso`, image profiles: `MIN-Live`)

## Image build quickstart

### Podman

The instructions below will use the `podman` command. Docker may work, but it's not tested or supported.

First, pull down the container of the required environment (CentOS Stream 10).

```bash
$ sudo podman pull quay.io/centos/centos:stream10-development
```

Assuming you're in the root directory of the Git checkout, set up the container:

```bash
$ sudo podman run --privileged --rm -it -v $PWD:/code:z -w /code quay.io/centos/centos:stream10-development /bin/bash
```

Once in the container environment, set up your development environment and run the image build (substitute `<image_type>` and `<image_profile>` for the appropriate settings):

```bash
# Install EPEL
[]: dnf --assumeyes install epel-release dnf-plugins-core
[]: dnf --assumeyes upgrade epel-release
[]: crb enable
# Install kiwi
[]$ dnf --assumeyes install kiwi
# Run the image build
[]$ kiwi-ng --type=<image_type> --profile=<image_profile> --color-output system build --description ./ --target-dir ./outdir
# Example
[]$ kiwi-ng --type=iso --profile=MIN-Live --color-output system build --description ./ --target-dir ./outdir
```

## Licensing

This is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, under version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
