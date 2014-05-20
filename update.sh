#!/bin/bash

exit_if_failed() {
  retval=$?

  if [ $retval -ne 0 ]; then
    echo "Exit code: ${retval}"
    exit $retval
  fi
}

echo "Executing: git remote update"
git remote update
exit_if_failed $?

echo "Executing: git pull origin master"
git pull origin master
exit_if_failed $?

echo "Executing: bundle install"
bundle install --path vendor/bundle
exit_if_failed $?

echo "Executing: bundle exec librarian-puppet install"
bundle exec librarian-puppet install

echo "Fixing files lacking user write bit"
find modules -type f ! -perm -u+w -exec chmod u+w {} \;

echo "Fixing files lacking group read bit"
find modules -type f ! -perm -g+r -exec chmod g+r {} \;

echo "Fixing files lacking other read bit"
find modules -type f ! -perm -o+r -exec chmod o+r {} \;

exit 0
