#!/bin/bash

echo "Fixing files lacking user write bit"
find modules -type f ! -perm -u+w -exec chmod u+w {} \;

echo "Fixing files lacking group read bit"
find modules -type f ! -perm -g+r -exec chmod g+r {} \;

echo "Fixing files lacking other read bit"
find modules -type f ! -perm -o+r -exec chmod o+r {} \;

exit 0
