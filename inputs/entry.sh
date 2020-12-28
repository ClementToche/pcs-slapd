#!/bin/bash

set -e

pcs-logger info '--------------------------------------------------'
pcs-logger info 'Personal Cloud Server - Open LDAP Server Starting '
pcs-logger info '--------------------------------------------------'
pcs-logger info 'openldap GID/UID'
pcs-logger info '--------------------------------------------------'
pcs-logger info "User uid:    $(id -u openldap)"
pcs-logger info "User gid:    $(getent group tls | cut -d ':' -f 3)"
pcs-logger info '--------------------------------------------------'

function initDB(){
    if [ ! -z "$(ls -A -I lost+found --ignore=.* /var/lib/ldap)" ] || \
       [ ! -z "$(ls -A -I lost+found --ignore=.* /etc/ldap/slapd.d)" ]
    then
        pcs-logger info 'Existing LDAP DB, no need to init'
        return 0
    fi

    # Create DB
    pcs-logger info 'Database empty, create new one'
    eval "cat <<EOF
$(</etc/ldap/ldap-deb.conf)
EOF
" 2> /dev/null | debconf-set-selections

    dpkg-reconfigure -f noninteractive slapd

    /usr/sbin/slapd -h "ldap:/// ldapi:///" -g openldap -u openldap -F /etc/ldap/slapd.d

    RootDN=$(ldapsearch -LLL -Y EXTERNAL -H ldapi:/// -b cn=config 2>/dev/null | grep "olcRootDN:" | grep -v config | cut -d ' ' -f 2)

    # Update password
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changeType: modify
replace: olcRootPW
olcRootPW:: ${PCS_LDAP_ADM_PWD}
EOF

    ldapmodify -x -w admin -D "${RootDN}" -H ldap://localhost <<EOF
dn: ${RootDN}
changeType: modify
replace: userPassword
userPassword:: ${PCS_LDAP_ADM_PWD}
EOF

    # Logging set-up
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changeType: modify
replace: olcLogLevel
olcLogLevel: stats
EOF

    chain_path=$(ls /mnt/certs/live/*/chain.pem)
    cert_path=$(ls /mnt/certs/live/*/cert.pem)
    privk_path=$(ls /mnt/certs/live/*/privkey.pem)

    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: ${chain_path}
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: ${cert_path}
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: ${privk_path}
EOF

    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changeType: modify
add: olcSecurity
olcSecurity: tls=1
EOF

    slapd_pid=$(pidof slapd)
    kill ${slapd_pid}
    while kill -0 ${slapd_pid} 2>/dev/null; do sleep 1; done
}

function checkDB(){
    pcs-logger info "TODO: Check DB"
    apt-get -y purge ldap-utils && apt-get -y autoremove && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 
}

initDB

/usr/sbin/slapd -h "ldap:///" -g openldap -u openldap -F /etc/ldap/slapd.d

tail -f /dev/null