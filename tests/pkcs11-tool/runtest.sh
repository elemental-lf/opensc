#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/opensc/Sanity/pkcs11-tool
#   Description: This is a sanity test for pkcs11-tool
#   Author: Jakub Jelen <jjelen@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="opensc"
## from OpenSC/src/tests/p11test/runtest.sh
SOPIN="12345678"
PIN="123456"
export GNUTLS_PIN=$PIN
GENERATE_KEYS=1
PKCS11_TOOL="pkcs11-tool"

function generate_cert() {
	TYPE="$1"
	ID="$2"
	LABEL="$3"

	# Generate key pair
	$PKCS11_TOOL --keypairgen --key-type="$TYPE" --login --pin=$PIN \
		--module="$P11LIB" --label="$LABEL" --id=$ID

	if [[ "$?" -ne "0" ]]; then
		echo "Couldn't generate $TYPE key pair"
		return 1
	fi

	# check type value for the PKCS#11 URI (RHEL7 is using old "object-type")
	TYPE_KEY="type"
	p11tool --list-all --provider="$P11LIB" --login | grep "object-type" && \
		TYPE_KEY="object-type"

	# Generate certificate
	certtool --generate-self-signed --outfile="$ID.cert" --template=cert.cfg \
		--provider="$P11LIB" --load-privkey "pkcs11:object=$LABEL;$TYPE_KEY=private" \
		--load-pubkey "pkcs11:object=$LABEL;$TYPE_KEY=public"
	# convert to DER:
	openssl x509 -inform PEM -outform DER -in "$ID.cert" -out "$ID.cert.der"
	# Write certificate
	#p11tool --login --write --load-certificate="$ID.cert" --label="$LABEL" \
	#	--provider="$P11LIB"
	$PKCS11_TOOL --write-object "$ID.cert.der" --type=cert --id=$ID \
		--label="$LABEL" --module="$P11LIB"

	rm "$ID.cert.der"

	# Extract public key, which is more digestible by some of the tools
	openssl x509 -inform PEM -in $ID.cert -pubkey > $ID.pub

	p11tool --login --provider="$P11LIB" --list-all
}

function card_setup() {
		ECC_KEYS=1
		case $1 in
			"softhsm")
				P11LIB="/usr/lib64/pkcs11/libsofthsm2.so"
				echo "directories.tokendir = .tokens/" > .softhsm2.conf
				mkdir ".tokens"
				export SOFTHSM2_CONF=".softhsm2.conf"
				# Init token
				softhsm2-util --init-token --slot 0 --label "SC test" --so-pin="$SOPIN" --pin="$PIN"
				;;
			"opencryptoki")
				# Supports only RSA mechanisms
				ECC_KEYS=0
				P11LIB="/usr/lib64/pkcs11/libopencryptoki.so"
				SO_PIN=87654321
				SLOT_ID=3 # swtok slot
				systemctl is-active pkcsslotd > /dev/null
				if [[ "$?" -ne "0" ]]; then
					echo "Opencryptoki needs pkcsslotd running"
					exit 1
				fi
				groups | grep pkcs11 > /dev/null
				if [[ "$?" -ne "0" ]]; then
					echo "Opencryptoki requires the user to be in pkcs11 group"
					exit 1
				fi
				echo "test_swtok" | /usr/sbin/pkcsconf -I -c $SLOT_ID -S $SO_PIN
				/usr/sbin/pkcsconf -u -c $SLOT_ID -S $SO_PIN -n $PIN
				;;
			*)
				echo "Error: Missing argument."
				exit 1;
				;;
		esac

		if [[ $GENERATE_KEYS -eq 1 ]]; then
			# Generate 1024b RSA Key pair
			generate_cert "RSA:1024" "01" "RSA_auth"
			# Generate 2048b RSA Key pair
			generate_cert "RSA:2048" "02" "RSA2048"
			if [[ $ECC_KEYS -eq 1 ]]; then
				# Generate 256b ECC Key pair
				generate_cert "EC:secp256r1" "03" "ECC_auth"
				# Generate 521b ECC Key pair
				generate_cert "EC:secp521r1" "04" "ECC521"
			fi
		fi
}

function card_cleanup() {
	case $1 in
		"softhsm")
			rm .softhsm2.conf
			rm -rf ".tokens"
			;;
	esac
	if [[ $GENERATE_KEYS -eq 1 ]]; then
		rm "0{1,2,3,4}.{cert,pub}"
	fi
}


rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm $PACKAGE
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "cp cert.cfg $TmpDir"
        rlRun "pushd $TmpDir"
        card_setup "softhsm"
        rlRun 'echo "data to sign (max 100 bytes)" > data'
    rlPhaseEnd

    for HASH in "" "SHA1" "SHA224" "SHA256" "SHA384" "SHA512"; do
        for SIGN_KEY in "01" "02"; do
            METHOD="RSA-PKCS"
            if [[ ! -z $HASH ]]; then
                METHOD="$HASH-$METHOD"
            fi
            rlPhaseStartTest "$METHOD: Sing & Verify (KEY $SIGN_KEY)"
                rlRun "$PKCS11_TOOL --id $SIGN_KEY -s -p $PIN -m $METHOD --module $P11LIB \
                       --input-file data --output-file data.sig"

                # OpenSSL verification
                if [[ -z $HASH ]]; then
                    rlRun "openssl rsautl -verify -inkey $SIGN_KEY.cert -in data.sig -certin"
                else
                    rlRun "openssl dgst -keyform PEM -verify $SIGN_KEY.pub -${HASH,,*} \
                           -signature data.sig data"
                fi

                # pkcs11-tool verification
                rlRun "$PKCS11_TOOL --id $SIGN_KEY --verify -m $METHOD --module $P11LIB \
                       --input-file data --signature-file data.sig"
                rlRun "rm data.sig"
            rlPhaseEnd

            METHOD="$METHOD-PSS"
            if [[ "$HASH" == "SHA512" ]]; then
                continue; # This one is broken
            fi
            rlPhaseStartTest "$METHOD: Sing & Verify (KEY $SIGN_KEY)"
                if [[ -z $HASH ]]; then
                    # hashing is done outside of the module. We chouse here SHA256
                    rlRun "openssl dgst -binary -sha256 data > data.hash"
                    HASH_ALGORITM="--hash-algorithm=SHA256"
                    VERIFY_DGEST="-sha256"
                    VERIFY_OPTS="-sigopt rsa_mgf1_md:sha256"
                else
                    # hashing is done inside of the module
                    rlRun "cp data data.hash"
                    HASH_ALGORITM=""
                    VERIFY_DGEST="-${HASH,,*}"
                    VERIFY_OPTS="-sigopt rsa_mgf1_md:${HASH,,*}"
                fi
                rlRun "$PKCS11_TOOL --id $SIGN_KEY -s -p $PIN -m $METHOD --module $P11LIB \
                       $HASH_ALGORITM --salt-len=-1 \
                       --input-file data.hash --output-file data.sig"

                # OpenSSL verification
                rlRun "openssl dgst -keyform PEM -verify $SIGN_KEY.pub $VERIFY_DGEST \
                       -sigopt rsa_padding_mode:pss  $VERIFY_OPTS -sigopt rsa_pss_saltlen:-1 \
                       -signature data.sig data"

                # pkcs11-tool verification
                rlRun "$PKCS11_TOOL --id $SIGN_KEY --verify -m $METHOD --module $P11LIB \
                       $HASH_ALGORITM --salt-len=-1 \
                       --input-file data.hash --signature-file data.sig"
                rlRun "rm data.{sig,hash}"
            rlPhaseEnd
        done

        # Skip hashed algorithms (do not support encryption & decryption)
        if [[ ! -z "$HASH" ]]; then
            continue;
        fi
        METHOD="RSA-PKCS"
        for ENC_KEY in "01" "02"; do
            rlPhaseStartTest "$METHOD: Encrypt & Decrypt (KEY $ENC_KEY)"
                # OpenSSL Encryption
                rlRun "openssl rsautl -encrypt -inkey $ENC_KEY.cert -in data \
                       -certin -out data.crypt"
                rlRun "$PKCS11_TOOL --id $ENC_KEY --decrypt -p $PIN -m $METHOD \
                       --module $P11LIB --input-file data.crypt > data.decrypted"
                rlRun "diff data{,.decrypted}"
                rlRun "rm data.{crypt,decrypted}"

                # TODO pkcs11-tool encryption
            rlPhaseEnd
        done
    done

    rlPhaseStartCleanup
        card_cleanup "softhsm"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
