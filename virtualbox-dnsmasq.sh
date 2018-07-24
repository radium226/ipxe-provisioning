#!/bin/bash

# https://ramonnogueira.wordpress.com/2013/03/29/simple-way-to-run-dnsmasq-for-virtualbox-guest-dhcp/

set -euo pipefail

export VIRTUALBOX_FOLDER_PATH="./.virtualbox"
export DNSMASQ_FOLDER_PATH="./.dnsmasq"

ipxe::make_iso()
{
  rm "./ipxe-efi.iso" || true
  cd "./ipxe/src"
  make clean
  rm -Rf "./bin" || true

  make \
    "bin-x86_64-efi/ipxe.efi" \
    EMBED="../../arch.ipxe" \
    DEBUG="script"


  mkdir -p "efi_tmp/EFI/BOOT" || true

  cp "bin-x86_64-efi/ipxe.efi" "efi_tmp/EFI/BOOT/bootx64.efi"
  genisoimage -o "../../ipxe-efi.iso" "./efi_tmp"
  cd "../.."

  test -f "./ipxe-efi.iso"
}

virtualbox::init()
{
  mkdir -p "${VIRTUALBOX_FOLDER_PATH}" || true
  mkdir -p "${VIRTUALBOX_FOLDER_PATH}/machines" || true
  (
    export VBOX_USER_HOME="${VIRTUALBOX_FOLDER_PATH}"

    VBoxManage setproperty \
      "machinefolder" "$( readlink -f "${VIRTUALBOX_FOLDER_PATH}" )/machines"
    VBoxManage setextradata global \
      "GUI/Input/HostKeyCombination" "65377"
  )
}

virtualbox::hard_drive::create()
{
  declare vdi_file_path="${1}"
  declare vdi_file_size_in_bytes="${2}"
  (
    export VBOX_USER_HOME="${VIRTUALBOX_FOLDER_PATH}"
    mkdir -p "$( dirname "${vdi_file_path}" )" || true
    VBoxManage createmedium \
  		disk \
  		--filename="${vdi_file_path}" \
  		--sizebyte="${vdi_file_size_in_bytes}"
  )
}

virtualbox::vm::create()
{
  declare vm_name="${1}"
  declare vm_ram_size_in_bytes="${2}"
  declare vdi_file_path="${3}"
  declare iso_file_path="${4}"

  (
    export VBOX_USER_HOME="${VIRTUALBOX_FOLDER_PATH}"

    VBoxManage createvm \
  		--name "${vm_name}" \
  		--ostype="ArchLinux_64" \
  		--register

    VBoxManage modifyvm \
  		"${vm_name}" \
  		--memory="$(( ${vm_ram_size_in_bytes} / 1024 / 1024 ))" \
  		--acpi="on" \
  		--boot1="dvd" \
  		--boot2="disk" \
  		--boot3="none" \
  		--firmware="efi" \
  		--vram="256"

  	VBoxManage storagectl "${vm_name}" \
  		--name="SATA Controller" \
  		--add="sata" \
  		--portcount=2

  	VBoxManage storageattach "${vm_name}" \
  		--storagectl="SATA Controller" \
  		--port=0 \
  		--device=0 \
  		--type="hdd" \
  		--medium="${vdi_file_path}"

    VBoxManage storageattach "${vm_name}" \
  		--storagectl="SATA Controller" \
  		--port=1 \
  		--device=0 \
  		--type="dvddrive" \
  		--medium="${iso_file_path}"

    VBoxManage modifyvm "${vm_name}" \
      --nic1="hostonly" \
      --hostonlyadapter1="vboxnet0"
  )
}

virtualbox::ui::start()
{
  (
    export VBOX_USER_HOME="${VIRTUALBOX_FOLDER_PATH}"

    VirtualBox
  )
}

virtualbox::start_vm()
{
  :
}

dnsmasq::init()
{
  mkdir -p "${DNSMASQ_FOLDER_PATH}" || true
}

dnsmasq::start()
{
  declare dnsmasq_iface="${1}"
  declare dnsmasq_dhcp_range="${2}"
  declare dnsmasq_domain="${3}"
  declare dnsmasq_host_name="${4}"
  declare dnsmasq_host_ip="${5}"

  {
    sudo resolvectl dns "${dnsmasq_iface}" "${dnsmasq_host_ip}"
    sudo dnsmasq \
      --conf-file="/dev/null" \
      --except-interface="lo0" \
      --interface="${dnsmasq_iface}" \
      --bind-interfaces \
      --dhcp-range="${dnsmasq_dhcp_range}" \
      --dhcp-leasefile="${DNSMASQ_FOLDER_PATH}/dnsmasq-leasefile.${dnsmasq_domain}" \
      --local="/${dnsmasq_domain}/" \
      --expand-hosts \
      --domain="${dnsmasq_domain}" \
      --address="/${dnsmasq_host_name}.${dnsmasq_domain}/${dnsmasq_host_ip}" \
      --log-queries \
      --log-facility=- \
      --user="$( id -un )"
    sudo resolvectl revert "${dnsmasq_iface}"
  } &
}

http_server::start()
{
  {
    sudo darkhttpd "./srv" --port "80"
  } &
}

http_server::stop()
{
  sudo pkill "darkhttpd" || true
}

dnsmasq::stop()
{
  #FIXME We need to use the good PID
  pkill "dnsmasq" || true
}

main()
{
  rm -Rf "${VIRTUALBOX_FOLDER_PATH}"

  #ipxe::make_iso

  dnsmasq::init
  virtualbox::init

  declare iface="vboxnet0"
  declare network_prefix="192.168.56"
  declare dnsmasq_lease_time="10m"
  declare dnsmasq_domain="virtualbox"
  declare netmask="255.255.255.0"
  declare host_name="virtualbox"
  declare host_ip="${network_prefix}.1"
  declare dnsmasq_dhcp_range="${network_prefix}.102,${network_prefix}.200,${dnsmasq_lease_time}"


  VBOX_USER_HOME=${VIRTUALBOX_FOLDER_PATH} \
    VBoxManage dhcpserver \
      remove \
        --ifname "${iface}"

  VBOX_USER_HOME=${VIRTUALBOX_FOLDER_PATH} \
    VBoxManage hostonlyif \
      ipconfig "${iface}" \
        --ip "${host_ip}" \
        --netmask "${netmask}"

  mkdir -p "./srv/arch/x86_64" || true
  cp \
    "./archlive/work/iso/arch/x86_64/airootfs.sfs" \
    "./srv/arch/x86_64/airootfs.sfs"
  cp \
    "./archlive/work/iso/arch/boot/x86_64/vmlinuz" \
    "./srv/vmlinuz"
  cp \
    "./archlive/work/iso/arch/boot/x86_64/archiso.img" \
    "./srv/archiso.img"
  cp \
    "./archlive/work/iso/arch/boot/intel_ucode.img" \
    "./srv/intel_ucode.img"

  http_server::start

  dnsmasq::start "${iface}" "${dnsmasq_dhcp_range}" "${dnsmasq_domain}" "${host_name}" "${host_ip}"

  declare vm_name="archlinux"
  declare vm_ram_size_in_bytes=$(( 2 * 1024 * 1024 * 1024 ))
  declare vdi_file_path="${VIRTUALBOX_FOLDER_PATH}/machines/${vm_name}/drive.vdi"
  declare vdi_file_size=$(( 2 * 1024 * 1024 * 1024 ))
  declare iso_file_path="./ipxe-efi.iso"

  virtualbox::hard_drive::create "${vdi_file_path}" "${vdi_file_size}"
  virtualbox::vm::create "${vm_name}" "${vm_ram_size_in_bytes}" "${vdi_file_path}" "${iso_file_path}"
  virtualbox::ui::start

  dnsmasq::stop
  http_server::stop
}

main "${@}"
