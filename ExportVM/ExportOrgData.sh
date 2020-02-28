#!/bin/sh -f

#------------------------------------------------------#
## Documentation:
## https://api.example.com/swagger-ui.html
#------------------------------------------------------#

test "$1" = '-D' && set -x && shift
API_ENDPOINT="https://api.example.com/api/latest"
test -f .api.token && API_TOKEN="`cat .api.token`"
test -f .export.cfg && source .export.cfg

test "$1" = '-h' && echo "usage: $0 <outputname>" 1>&2 && exit
test "$1" = '' && echo 'parameter outputfile is missing' 1>&2 && exit
OUTFILE="$1.json"

## needs package "jq" to pretty-print and syntax check
(
  echo '{'
    # Get Users
    echo '"Users": '
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -G "https://api.example.com/api/latest/users"
  echo ','
    # Get Templates
    echo '"Templates": '
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "https://api.example.com/api/latest/templates"
  echo ','
    # Get Applications
    echo '"Applications": '
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "https://api.example.com/api/latest/applications"
  echo '}'
) | jq . > ${OUTFILE}

