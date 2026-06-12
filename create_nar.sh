#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
#
# SPDX-License-Identifier: UPL-1.0

dir=$(dirname "${0}")

pushd "${dir}" > /dev/null

# Build
zig build -Drelease

# Create updates.txt
pushd 'public' > /dev/null
echo 'charset,UTF-8' > updates.txt
for f in $(find . -type f)
do
    echo "file,${f#./}\x01$(md5sum ${f} | awk '{print $1}')\x01size=$(wc -c ${f} | awk '{print $1}')\x01" >> updates.txt
done
cp 'updates.txt' 'ghost/master/'

# Create .nar
zip -r9 '../ghost_in_a_nutshell.nar' .

popd > /dev/null
popd > /dev/null
