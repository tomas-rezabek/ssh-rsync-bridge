#!/usr/bin/bash
set -euo pipefail
source .env
# --- logovani / kontrola chyb ---
# pokud neco skonci chybou, skript ukoncime
die() { echo "ERROR: $*" >&2; exit 1; }
# kontrola prikazu
need() { command -v "$1" >/dev/null 2>&1 || die "Chybějí potřebné příkazy: $1"; }
# Funkce co vycisti klice
cleanup() {
echo "Čístím klíče..."
  # Vyčístím klíč na cílovém serveru v authorized_keys
ssh -i "$LOCAL_SSH_KEY" -p "$DST_PORT" "$DST_USER@$DST_SERVER.$HOSTNAME" "if [ -f .ssh/authorized_keys ]; then
    sed -i.backup "/[[:space:]]${TAG}\$/d" .ssh/authorized_keys
  fi" || true

# Vyčistím klíče na zdrojovém serveru v .ssh
ssh -i "$LOCAL_SSH_KEY" -p "$SRC_PORT" "$SRC_USER@$SRC_SERVER.$HOSTNAME" "cd .ssh; rm -f ${REMOTE_KEY_PATH} ${REMOTE_KEY_PATH}.pub" || true

# Vyčistím klíč na zdrojovém serveru v authorized_keys
ssh -i "$LOCAL_SSH_KEY" -p "$SRC_PORT" "$SRC_USER@$SRC_SERVER.$HOSTNAME" "if [ -f .ssh/authorized_keys ]; then
    sed -i.backup "/[[:space:]]${TAG}\$/d" .ssh/authorized_keys
  fi" || true

# jako posledni smazu loklani .ssh 
rm -f "$LOCAL_SSH_KEY" "$LOCAL_SSH_KEY.pub" "$LOCAL_TMP_PUB" || true
echo
echo "HOTOVO, vše uklizeno"
}

need ssh
need ssh-copy-id
need scp
need rsync
need mktemp
need date

# --- input data ---

source .env

# read -r -p "Uživatel zdrojového serveru: " SRC_USER
# read -r -p "Název zdrojového serveru, například arlene: " SRC_SERVER
# read -r -p "Cesta k adresáři zdrojového serveru: " SRC_PATH
# read -r -p "Port zdrojového serveru: " SRC_PORT

# read -r -p "Uživatel cílového serveru: " DST_USER
# read -r -p "Název cílového serveru, například barker: " DST_SERVER
# read -r -p "Cesta k adresáři cílového serveru: " DST_PATH
# read -r -p "Port cílového serveru: " DST_PORT

# unikatni tag
TAG="tmp-a2b-$(date +%Y%m%d%H%M%S)-$$"
SSH_DIR=".ssh"
LOCAL_SSH_KEY="$SSH_DIR/$TAG"

# Pokud .ssh neexistuje, vyvoříme a nastavíme pravidla
if [ ! -d "$SSH_DIR" ]; then
  mkdir -p .ssh
  chmod 700 .ssh
fi


# Vygenerujeme dočasný SSH klíč
echo "Generuji dočasný SSH klíč..."
ssh-keygen -t ed25519 -f "$LOCAL_SSH_KEY" -C "${TAG}" -q -N ""

# Nastavíme vhodná pravidla
echo "Nastavuji vhodná pravidla pro klíč..."
chmod 600 "$LOCAL_SSH_KEY"
chmod 644 "$LOCAL_SSH_KEY.pub"

# Klíč zkopírujeme na zdrojový server
echo "Kopíruji SSH klíč na zdrojový server, zadej heslo"
ssh-copy-id -i "$LOCAL_SSH_KEY.pub" "$SRC_USER@$SRC_SERVER.$HOSTNAME"

echo "Kopíruji SSH klíč na cílový server, zadej heslo"
# Klíč zkopírujeme na cílový server
ssh-copy-id -i "$LOCAL_SSH_KEY.pub" "$DST_USER@$DST_SERVER.$HOSTNAME"

# Generování základních cest
echo "Generuji cesty pro ssh..."
REMOTE_KEY_DIR=".ssh"
REMOTE_KEY_PATH="id_ed25519_${TAG}"
REMOTE_PUB_PATH="${REMOTE_KEY_DIR}/${REMOTE_KEY_PATH}.pub"

# Generuji dočasný klíč na zdrojovém serveru
ssh -i "$LOCAL_SSH_KEY" -p "$SRC_PORT" "$SRC_USER@$SRC_SERVER.$HOSTNAME" "cd .ssh; ssh-keygen -t ed25519 -N '' -f ${REMOTE_KEY_PATH} -C '${TAG}' >/dev/null"

# Kopíruji dočasný klíč do dočasného souboru, po skončení skriptu se smaže
LOCAL_TMP_PUB="$(mktemp)"
trap cleanup EXIT
# Stahuji dočasný klíč ze drojového serveru
scp -i "$LOCAL_SSH_KEY" -P "$SRC_PORT" "$SRC_USER@$SRC_SERVER.$HOSTNAME:${REMOTE_PUB_PATH}" "$LOCAL_TMP_PUB" >/dev/null

# Uložíme obsah klíče
PUBKEY_LINE="$(cat "$LOCAL_TMP_PUB")"
[[ -n "$PUBKEY_LINE" ]] || die "Public key je prázdný, něco se pokazilo."

# Na cílovém serveru vytvoříme authorized_keys adresář
ssh -i "$LOCAL_SSH_KEY" -p "$DST_PORT" "$DST_USER@$DST_SERVER.$HOSTNAME" "cd .ssh; touch authorized_keys; chmod 600 authorized_keys"

# Do adresáře .ssh/authorized_keys vložíme obsah klíče
ssh -i "$LOCAL_SSH_KEY" -p "$DST_PORT" "$DST_USER@$DST_SERVER.$HOSTNAME" "printf '%s %s\n' \"${PUBKEY_LINE}\" \"${TAG}\" >> .ssh/authorized_keys"

# Příkaz rsync, který spustí SSH připojení a kopírování dat ze drojového serveru na cílový
## -a = archiv, -v = logovani, -z = komprese, --progress = procenta a rychlost
RSYNC_CMD="rsync -avz --progress -e \"ssh -p ${DST_PORT} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -i .ssh/${REMOTE_KEY_PATH}\" \"${SRC_PATH}\" \"${DST_USER}@${DST_SERVER}.${HOSTNAME}:${DST_PATH}\""

echo
echo "Spouštím rsync příkaz..."
#echo "$RSYNC_CMD"
echo
ssh -i "$LOCAL_SSH_KEY" -p "$SRC_PORT" "$SRC_USER@$SRC_SERVER.$HOSTNAME" "$RSYNC_CMD"
echo
echo "HOTOVO, soubory v pořádku překopírovány"
echo