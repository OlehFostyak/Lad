#!/bin/bash
# Creates Lad's own code-signing identity, "Lad Local Code Signing", in a separate keychain locked
# with a password you choose (make setup-signing). `make bundle` unlocks it only while codesign
# runs and locks it again, so no other program can sign itself as Lad and inherit its
# Accessibility permission. Run it in a terminal tab of your own: it asks for the new password.
#
# The certificate is self-signed for code signing only (CA:FALSE, EKU codeSigning), 10 years.
set -euo pipefail

KEYCHAIN="${SIGN_KEYCHAIN:-$HOME/Library/Keychains/lad-signing.keychain-db}"
NAME="Lad Local Code Signing"
OPENSSL=/usr/bin/openssl   # LibreSSL: its PKCS#12 files are the kind `security import` reads
LOCK_AFTER_SECONDS=300

if [ -e "$KEYCHAIN" ]; then
  echo "error: $KEYCHAIN already exists; delete it first (security delete-keychain \"$KEYCHAIN\")" >&2
  exit 1
fi

work="$(mktemp -d)"
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT

# create-keychain adds the keychain to the search list; it is put back as it was, so other apps
# never look into Lad's keychain (and never ask to unlock it). make bundle names it explicitly.
search_list=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"
  search_list+=("${line%\"}")
done < <(security list-keychains -d user)

echo "Choose a password for Lad's signing keychain (you will type it at every make install):"
security create-keychain "$KEYCHAIN"
security list-keychains -d user -s "${search_list[@]}"
security set-keychain-settings -l -u -t "$LOCK_AFTER_SECONDS" "$KEYCHAIN"

cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
  -config "$work/cert.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
transfer="$("$OPENSSL" rand -hex 24)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/identity.p12" -passout "pass:$transfer"

echo "Unlock the new keychain to import the identity (the same password):"
security unlock-keychain "$KEYCHAIN"
# Only codesign may use the key. The partition list lets Apple's codesign use it without a GUI
# prompt, but only while the keychain is unlocked, which `make bundle` does for the signing alone.
security import "$work/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$transfer" -T /usr/bin/codesign
echo "Once more, to let codesign use the key while the keychain is unlocked:"
security set-key-partition-list -S apple-tool:,apple: -s "$KEYCHAIN" >/dev/null
security lock-keychain "$KEYCHAIN"

security find-identity -p codesigning "$KEYCHAIN"
echo "done: \"$NAME\" is in $KEYCHAIN (locked). Next: make install"
