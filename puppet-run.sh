#!/bin/bash

readonly DEF_ENV="${ENV:-production}"
readonly DEF_PUPPET_ARGS=""
readonly DEF_DEBUG=0
readonly PROGNAME=$(basename $0)

usage () {

cat << EOF
usage: $(basename $0) [OPTIONS] [environmentpath]

Puppet masterless agent script.

OPTIONS:

  -e, --env       Puppet environment (default: $DEF_ENV)
  -a, --args      Args passed to Puppet (default: $DEF_PUPPET_ARGS)
  -d, --debug     Show debug output
  -h, --help      Show this message

EXAMPLE:

Apply site.pp located at /apps/puppet/environments/production/manifests

${PROGNAME} -e production -a '--noop' /apps/puppet/environments

EOF
}

ARGS=`getopt -o e:,a:,d,h -l env:,args:,debug,help -n "$0" -- "$@"`

[ $? -ne 0 ] && { usage; exit 1; }

eval set -- "${ARGS}"

while true; do
  case "$1" in
    -h|--help) usage ; exit 0 ;;
    -e|--env) ENV=$2 ; shift 2 ;;
    -a|--args) PUPPET_ARGS=$2 ; shift 2 ;;
    -d|--debug) DEBUG=1 ; QUIET=0 shift ;;
    --) shift ; break ;;
    *) break ;;
  esac
done

if [ $# -lt 1 ]; then
  echo "Missing environmentpath argument"
  exit 1
fi

ENVIRONMENTPATH=$1
ENVIRONMENT="${ENV:-$DEF_ENV}"
PUPPET_ARGS="${PUPPET_ARGS:-$DEF_PUPPET_ARGS}"
DEBUG=${DEBUG:-$DEF_DEBUG}

[ $DEBUG -eq 1 ] && set -x


CONFDIR="${ENVIRONMENTPATH}/${ENVIRONMENT}"
SITEPP="${CONFDIR}/manifests/site.pp"

CMD="puppet apply --confdir ${CONFDIR} ${SITEPP} --write-catalog-summary ${PUPPET_ARGS}"

echo $CMD

