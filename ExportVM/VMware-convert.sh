#!/bin/sh -f

test "$1" = '-D' && set -x && shift

uuid="$1"
name="$2"

META="${name}.meta"
if test \! -f "${META}"; then
    echo "Metadata missing (${META})" 1>&2
    exit
fi
gd() { jq ".${id}" < "${META}"; }
bmem=`gd memory`
vmem=`expr $bmem / 1024 / 1024`
vcpu=`gd cpu`
desc=`gd description`

disk="${uuid}.vmdk"
flat="${name}-flat.vmdk"
dscr="${name}.vmdk"
meta="${name}.vmx" <<EOM

thin='thin'
if test -f "${disk}" && test \! -f "${flat}"; then
    vmkfstool -d $thin -i "${disk}" "$dscr"
elif test 0 != 0; then
    size=`stat -c '%s' "${disk}"`
    ctrl='lsilogic'
    vmkfstool -c $size -a $ctrl -d $thin "$dscr"
    mv "${disk}" "${flat}"
fi

cat > "${name}.vmx" <<EOM
.encoding = "UTF-8"
config.version = "8"
displayName = "${name}"
ethernet0.addressType = "generated"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "e1000"
floppy0.present = "FALSE"
guestOS = "other3xlinux-64"
memsize = "${vmem}`"
mem.hotadd = "TRUE"
numvcpus = "${vcpu}"
vcpu.hotadd = "TRUE"
virtualHW.productCompatibility = "hosted"
virtualHW.version = "8"
pciBridge0.present = "TRUE"
pciBridge4.functions = "8"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.reset = "soft"
powerType.suspend = "soft"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "Yocto_Build_Appliance.vmdk"
sound.autodetect = "TRUE"
sound.fileName = "-1"
sound.present = "TRUE"
usb.present = "TRUE"
vmci0.present = "TRUE"
EOM

