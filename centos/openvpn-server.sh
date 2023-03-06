#!/bin/bash
#
# https://github.com/Nyr/openvpn-install
# https://www.howtoforge.com/tutorial/how-to-install-openvpn-server-and-client-with-easy-rsa-3-on-centos-7/

ip_start="10.10.10"
ip_mask="255.255.255.0"

RED=$(printf '\033[31m')
YELLOW=$(printf '\033[33m')
RESET=$(printf '\033[m')
echo_error() {
  echo "${RED}error: $*${RESET}" >&2
}
echo_warn() {
  echo "${YELLOW}warn: $*${RESET}" >&2
}
echo_info() {
  echo "$*" >&2
}

next_ip() {
    IP=$1
    IP_HEX=$(echo "$IP" |sed -e 's/\./ /g' |xargs printf '%.2X%.2X%.2X%.2X\n')
    NEXT_IP_HEX=$(echo $(( 0x$IP_HEX + 1 )) |xargs printf %.8X)
    NEXT_IP=$(echo "$NEXT_IP_HEX" |sed -r 's/(..)/0x\1 /g' |xargs printf '%d.%d.%d.%d\n')
    echo "$NEXT_IP"
}

# Generates the custom client.ovpn
new_client() {
  {
    cat /etc/openvpn/client/client-common.txt
    echo "<ca>"
    cat /etc/openvpn/easy-rsa/3/pki/ca.crt
    echo "</ca>"
    echo "<cert>"
    sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/easy-rsa/3/pki/issued/"$1".crt
    echo "</cert>"
    echo "<key>"
    cat /etc/openvpn/easy-rsa/3/pki/private/"$1".key
    echo "</key>"
  } >/etc/openvpn/client/"$1".ovpn
}

new_ccd() {
  MAX_IP=$(awk '/./{line=$0} END{print line}' /etc/openvpn/client/ips.txt |awk '{print $1}')
  NEXT_IP=$(next_ip "$MAX_IP")
  NEXT_IP=$(next_ip "$NEXT_IP")
  NEXT_NEXT_IP=$(next_ip "$NEXT_IP")
  echo "$NEXT_IP $1" >>/etc/openvpn/client/ips.txt
  echo "ifconfig-push $NEXT_IP $NEXT_NEXT_IP" >/etc/openvpn/ccd/"$1"
}

if [[ -e /etc/openvpn/server/server.conf ]]; then
  echo_info "Looks like OpenVPN is already installed."
  echo
  echo_info "What do you want to do?"
  echo_info "   1) Add a new user"
  echo_info "   2) Revoke an existing user"
  echo_info "   3) Remove OpenVPN"
  echo_info "   4) Exit"
  read -rp "${YELLOW}Select an option [1]: ${RESET}" OPTION
  [[ -z "$OPTION" ]] && OPTION=1
  until [[ -z "$OPTION" || "$OPTION" =~ ^[1-4]$ ]]; do
    echo_error "Invalid selection: $OPTION"
    read -rp "${YELLOW}Select an option [1]: ${RESET}" OPTION
  done
  [[ -z "$OPTION" ]] && OPTION=1

  case "$OPTION" in
  1)
    echo
    echo_info "Tell me a name for the client certificate. format: ^[0-9a-zA-Z_-]$"
    read -rp "${YELLOW}Client name: ${RESET}" CLIENT_NAME
    until [[ "$CLIENT_NAME" =~ ^[0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]+$ && ! -f /etc/openvpn/easy-rsa/3/pki/issued/"$CLIENT_NAME".crt ]]; do
      echo_error "Client name is invalid or already exists: $CLIENT_NAME"
      read -rp "${YELLOW}Client name: ${RESET}" CLIENT_NAME
    done

    cd /etc/openvpn/easy-rsa/3/ || {
      echo_error "/etc/openvpn/easy-rsa/3/ not exists"
      exit 1
    }
    # Build Client Key
    echo "$CLIENT_NAME" | ./easyrsa gen-req "$CLIENT_NAME" nopass
    echo 'yes' | ./easyrsa sign-req client "$CLIENT_NAME"
    # Optional: Generate the CRL Key
    ./easyrsa gen-crl
    cp pki/issued/"$CLIENT_NAME".crt /etc/openvpn/client/
    cp pki/private/"$CLIENT_NAME".key /etc/openvpn/client/
    # Copy CRL Key
    rm -f /etc/openvpn/server/crl.pem
    cp pki/crl.pem /etc/openvpn/server/
    new_client "$CLIENT_NAME"
    new_ccd "$CLIENT_NAME"
    echo
    echo_info "Client $CLIENT_NAME added, configuration is available at: /etc/openvpn/client/$CLIENT_NAME.ovpn"
    echo_info "If you want to add more clients, just run this script again!"
    exit
    ;;
  2)
    CLIENT_COUNT=$(tail -n +2 /etc/openvpn/easy-rsa/3/pki/index.txt |grep -c "^V")
    if [[ "$CLIENT_COUNT" == 0 ]]; then
      echo
      echo_info "You have no existing clients!"
      exit
    fi
    echo
    echo_info "Select the existing client certificate you want to revoke:"
    tail -n +2 /etc/openvpn/easy-rsa/3/pki/index.txt |grep "^V" |cut -d '=' -f 2 |nl -s ') '
    read -rp "${YELLOW}Select one client: ${RESET}" CLIENT_SELECTED
    until [[ $CLIENT_SELECTED =~ ^[1-9][0-9]*$ && $CLIENT_SELECTED -gt 0 && $CLIENT_SELECTED -le $CLIENT_COUNT ]]; do
      echo_error "invalid selection: $CLIENT_SELECTED"
      read -rp "${YELLOW}Select one client: ${RESET}" CLIENT_SELECTED
    done
    CLIENT_NAME=$(tail -n +2 /etc/openvpn/easy-rsa/3/pki/index.txt |grep "^V" |cut -d '=' -f 2 |sed -n "$CLIENT_SELECTED"p)
    echo
    read -rp "${YELLOW}Do you really want to revoke access for client $CLIENT_NAME? [y/N]: ${RESET}" REVOKE
    until [[ "$REVOKE" =~ ^[yYnN]$ ]]; do
      echo_error "invalid selection: $REVOKE"
      read -rp "${YELLOW}Do you really want to revoke access for client $CLIENT_NAME? [y/N]: ${RESET}" REVOKE
    done
    if [[ "$REVOKE" =~ ^[yY]$ ]]; then
      cd /etc/openvpn/easy-rsa/3/ || {
        echo_error "/etc/openvpn/easy-rsa/3/ not exists"
        exit 1
      }
      ./easyrsa --batch revoke "$CLIENT_NAME"
      ./easyrsa gen-crl
      rm -f pki/reqs/"$CLIENT_NAME".req
      rm -f pki/private/"$CLIENT_NAME".key
      rm -f pki/issued/"$CLIENT_NAME".crt
      rm -f /etc/openvpn/server/crl.pem
      rm -f /etc/openvpn/ccd/"$CLIENT_NAME"
      cp pki/crl.pem /etc/openvpn/server/
      echo
      echo_info "Certificate for client $CLIENT_NAME revoked!"
    else
      echo
      echo_info "Certificate revocation for client $CLIENT_NAME aborted!"
    fi
    exit
    ;;
  3)
    echo
    read -rp "${YELLOW}Do you really want to remove OpenVPN? [y/N]: ${RESET}" REMOVE
    until [[ "$REMOVE" =~ ^[yYnN]$ ]]; do
      echo_error "invalid selection: $REMOVE"
      read -rp "${YELLOW}Do you really want to remove OpenVPN? [y/N]: ${RESET}" REMOVE
    done
    if [[ "$REMOVE" =~ ^[yY]$ ]]; then
      sed -i "s/^sshd:$IP_START.:allow/# &/" /etc/hosts.allow
      sed -i 's/^sshd:ALL/# &/' /etc/hosts.deny
      # eth0
      NET_CARD=$(ip route get 114.114.114.114 |awk 'NR==1 {print $(NF-2)}')
      OPENVPN_IP=$(grep '^server ' /etc/openvpn/server/server.conf |awk '{print $2}')
      firewall-cmd --permanent --zone=public --remove-service=openvpn
      firewall-cmd --permanent --zone=trusted --remove-interface=tun0
      firewall-cmd --permanent --direct --remove-passthrough ipv4 -t nat -A POSTROUTING -s "$OPENVPN_IP"/24 -o "$NET_CARD" -j MASQUERADE
      firewall-cmd --remove-service=openvpn
      firewall-cmd --zone=trusted --remove-interface=tun0
      firewall-cmd --direct --remove-passthrough ipv4 -t nat -A POSTROUTING -s "$OPENVPN_IP"/24 -o "$NET_CARD" -j MASQUERADE
      firewall-cmd --reload
      systemctl stop openvpn-server@server
      systemctl disable openvpn-server@server
      yum remove openvpn -y
      rm -rf /etc/openvpn
      echo
      echo_info "OpenVPN removed!"
    else
      echo
      echo_info "Removal aborted!"
    fi
    exit
    ;;
  4) exit ;;
  esac
else
  echo_info "What IPv4 address should the OpenVPN server bind to?"
  IP_PROMOTE=$(ip addr |grep inet |grep -v inet6 |awk '{print $2}' |grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' |grep -vE '127' |sort |uniq |nl -s ') ')
  IP_COUNT=$(echo "$IP_PROMOTE" |wc -l |awk '{print $1}')
  echo_info "$IP_PROMOTE"
  read -rp "${YELLOW}Local IPv4 address: ${RESET}" IP_SELECTED
  until [[ "$IP_SELECTED" =~ ^[1-9][0-9]*$ && $IP_SELECTED -gt 0 && $IP_SELECTED -le $IP_COUNT ]]; do
    echo_error "invalid selection: $IP_SELECTED"
    read -rp "${YELLOW}Local IPv4 address [1]: ${RESET}" IP_SELECTED
  done

  LAN_IP=$(echo "$IP_PROMOTE" |sed -n "$IP_SELECTED"p |awk '{print $2}' |sed 's/[0-9]*$/0/')
  WAN_IP=$(wget -4qO- "http://whatismyip.akamai.com/" || curl -4Ls "htyip.akamai.com/")
  echo_info "Wan IPv4 address: $WAN_IP"

  # Allow a limited set of characters to avoid conflicts
  echo_info "Tell me a name for the client certificate. format: ^[0-9a-zA-Z_-]$"
  read -rp "${YELLOW}Client name: ${RESET}" CLIENT_NAME
  until [[ "$CLIENT_NAME" =~ ^[0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]+$ && ! -f /etc/openvpn/easy-rsa/3/pki/issued/"$CLIENT_NAME".crt ]]; do
    echo_error "Client name is invalid or already exists: $CLIENT_NAME"
    read -rp "${YELLOW}Client name: ${RESET}" CLIENT_NAME
  done

  read -n1 -r -p "${GREEN}Press any key to continue...${RESET}"

  # Step 1 - Install OpenVPN and Easy-RSA
  # easy-rsa: 3.0.6
  # openvpn: 2.4.8

  yum install epel-release -y
  yum install openvpn easy-rsa -y

  # Step 2 - Configure Easy-RSA 3
  cp -r /usr/share/easy-rsa /etc/openvpn/

  # Step 3 - Build OpenVPN Keys
  cd /etc/openvpn/easy-rsa/3/ || {
    echo_error "/etc/openvpn/easy-rsa/3/ not exists"
    exit 1
  }
  # Initialization and Build CA
  ./easyrsa init-pki
  echo 'Easy-RSA CA' | ./easyrsa build-ca nopass
  # Build Server Key
  echo 'server' | ./easyrsa gen-req server nopass
  echo 'yes' | ./easyrsa sign-req server server
  # Build Client Key
  echo "$CLIENT_NAME" | ./easyrsa gen-req "$CLIENT_NAME" nopass
  echo 'yes' | ./easyrsa sign-req client "$CLIENT_NAME"
  # Optional: Generate the CRL Key
  ./easyrsa gen-crl
  # Build Diffie-Hellman Key
  ./easyrsa gen-dh
  # Copy Certificates Files
  cp pki/ca.crt /etc/openvpn/server/
  cp pki/issued/server.crt /etc/openvpn/server/
  cp pki/private/server.key /etc/openvpn/server/
  # Copy Client Key and Certificate
  cp pki/ca.crt /etc/openvpn/client/
  cp pki/issued/"$CLIENT_NAME".crt /etc/openvpn/client/
  cp pki/private/"$CLIENT_NAME".key /etc/openvpn/client/
  # Copy DH and CRL Key
  cp pki/dh.pem /etc/openvpn/server/
  cp pki/crl.pem /etc/openvpn/server/

  # Step 4 - Configure OpenVPN
  cd /etc/openvpn/ || {
    echo_error "/etc/openvpn/ not exists"
    exit 1
  }
  mkdir ccd
  echo "$IP_START.1 master" >client/ips.txt

  echo "# OpenVPN Port, Protocol and the Tun
port 1194
proto udp
dev tun

# OpenVPN Server Certificate - CA, server key and certificate
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key

# DH and CRL key
dh /etc/openvpn/server/dh.pem
crl-verify /etc/openvpn/server/crl.pem

# Network Configuration - Internal network
# Redirect all Connection through OpenVPN Server
server $IP_START.0 $IP_MASK
# push \"redirect-gateway def1\"
push \"route $IP_START.0 $IP_MASK\"
push \"route $LAN_IP $IP_MASK\"

client-config-dir /etc/openvpn/ccd/

# Enable multiple client to connect with same Certificate key
# duplicate-cn

# TLS Security
cipher AES-256-CBC
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
auth SHA512
auth-nocache

# Other Configuration
keepalive 20 60
persist-key
persist-tun
comp-lzo yes
daemon
user nobody
group nobody
ifconfig-pool-persist /etc/openvpn/client/ipp.txt

# OpenVPN Log
log-append /var/log/openvpn/openvpn.log
verb 3
" >server/server.conf
  mkdir /var/log/openvpn

  # Step 5 - Enable Port-Forwarding and Configure Routing Firewalld
  # eth0
  NET_CARD=$(ip route get 114.114.114.114 |awk 'NR==1 {print $(NF-2)}')
  systemctl start firewalld
  systemctl enable firewalld
  grep -Eq 'net.ipv4.ip_forward ?= ?1' /etc/sysctl.conf || {
    echo 'net.ipv4.ip_forward = 1' >>/etc/sysctl.conf
  }
  sysctl -p
  firewall-cmd --permanent --add-service=openvpn
  firewall-cmd --permanent --zone=trusted --add-interface=tun0
  firewall-cmd --permanent --zone=trusted --add-masquerade
  firewall-cmd --permanent --direct --passthrough ipv4 -t nat -A POSTROUTING -s $IP_START.0/24 -o "$NET_CARD" -j MASQUERADE
  firewall-cmd --reload
  systemctl start openvpn-server@server
  systemctl enable openvpn-server@server

  # Step 6 - OpenVPN Client Setup
  cd /etc/openvpn/client/ || {
    echo_error "/etc/openvpn/client/ not exists"
    exit 1
  }
  echo "client
dev tun
proto udp

remote $WAN_IP 1194

cipher AES-256-CBC
auth SHA512
auth-nocache
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256

resolv-retry infinite
compress lzo
nobind
persist-key
persist-tun
mute-replay-warnings
verb 3" >client-common.txt

  new_client "$CLIENT_NAME"
  new_ccd "$CLIENT_NAME"
  echo
  echo_info "Finished!"
  echo
  echo_info "Your client configuration is available at: /etc/openvpn/client/$CLIENT_NAME.ovpn"
  echo_info "If you want to add more clients, just run this script again!"

  # Step 7 Enable SSH only when connected to VPN (OpenVPN)
  echo
  echo_info 'You could execute the following commands manually'
  echo_info "echo \"sshd:$IP_START.:allow\" >> /etc/hosts.allow"
  echo_info 'echo "sshd:ALL" >> /etc/hosts.deny'
  echo_info 'firewall-cmd --permanent --zone=public --add-port=80/tcp'
  echo_info 'firewall-cmd --add-masquerade --permanent'
  echo_info 'firewall-cmd --reload'
fi
