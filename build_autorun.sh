#!/bin/bash

set -e

NAME=$0
TMP_FOLDER=

usage()
{
	echo "Usage: $NAME -k keyfile -s script -o out_script [-f files]"
	if [[ ! -z "$TMP_FOLDER" ]]; then
		rm -rf "$TMP_FOLDER"
	fi

	exit 1
}

cp_err()
{
	if [[ -f "$1" ]]; then
		cp "$1" $TMP_FOLDER/$2
	else
		echo $1 does not exist
		rm -rf "$TMP_FOLDER"
		exit 1
	fi
}

AUTOFILE="ttfile.bin"

KEYFILE=
SCRIPT=
OUT_SCRIPT=
FILES=()

while [[ $# -gt 0 ]]; do
	case $1 in
	-k|--keyfile)
		KEYFILE="$2"
		shift 2
		;;
	-s|--script)
		SCRIPT="$2"
		shift 2
		;;
	-o|--out_script)
		OUT_SCRIPT="$2"
		shift 2
		;;
	-f|--file)
		FILES+=("$2")
		shift 2
		;;
	-*|--*)
		usage
		;;
	*)
		usage
		;;
 	esac
done

if [[ -z "$KEYFILE" ]]; then
	echo "No key file supplied"
	usage
fi

if [[ -z "$SCRIPT" ]]; then
	echo "No script supplied"
	usage
fi



#TODO check if all parameters
#TODO out_script optional


TMP_FOLDER=$(mktemp -d)

cp_err $SCRIPT script.sh
chmod -x $TMP_FOLDER/script.sh


if [[ ! -z "$OUT_SCRIPT" ]]; then
	cp_err $OUT_SCRIPT out_script.sh
	chmod -x $TMP_FOLDER/out_script.sh
fi

for ((i = 0; i < ${#FILES[@]}; i++))
do
	if [[ -e "${FILES[$i]}" ]]; then
		cp -r "${FILES[$i]}" $TMP_FOLDER/
	else
		echo ${FILES[$i]} does not exist
		rm -rf "$TMP_FOLDER"
		exit 1
	fi
done

TMP_RESULTS=$(mktemp -d)

tar \
	--owner=0 --group=0 \
	-C $TMP_FOLDER \
	-czf $TMP_RESULTS/data.tar.gz .

openssl dgst -sha256 -sign "$KEYFILE" -out $TMP_RESULTS/sign $TMP_RESULTS/data.tar.gz

#TODO crc and extra CPIO options
cpio --quiet -H crc -D $TMP_RESULTS -ov << EOF > ttfile.bin 2>/dev/null
sign
data.tar.gz
EOF

rm -rf $TMP_FOLDER
rm -rf $TMP_RESULTS

