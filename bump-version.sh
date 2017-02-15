#!/bin/bash


current_branch=$(git rev-parse --abbrev-ref HEAD)
current_version=$(echo $current_branch | cut -d '/' -f2)
current_version="0.9.1"
if [[ $current_version =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "current version is ${current_version}"
else
    echo "Something is wrong with your version. the version format must be X.Y.Z" >&2
    exit 1
fi

sed -i "" "s/^STEVE_VERSION=\".*\"$/STEVE_VERSION=\"${current_version}\"/g" sa/steve.sh

echo "sa/steve.sh is updated, ", $(grep "STEVE_VERSION=" sa/steve.sh)
exit 0
