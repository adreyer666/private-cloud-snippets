#!/bin/bash -f

#------------------------------------------------------#
## Documentation:
## https://api.example.com/swagger-ui.html
#------------------------------------------------------#

test "$1" = '-D' && set -x && shift
API_ENDPOINT="https://api.example.com/api/latest"
test -f .api.token && API_TOKEN="`cat .api.token`"
test -f .export.cfg && source .export.cfg
VERB=1
EXPORTDIR='/templates'

help() {
    cat <<EOM
usage: `basename $0` [-h] [-v] [-l] [-x] [-e <export dir>] [-s] [-a | -t | -u <VM uuid>]

options:
        -h      show this help
        -v      be more verbose
        -l      limit the scope (Experimental)
        -vmx    create VMX file (Experimental)
        -e      specify export dir for VMDK/VMX file
        -a      dump app metadata
        -t      dump template metadata
        -s      shut down APP (templating needs shutdown)
        -x      export/convert listed/all APPs/templates
	-u      UUID (comma separated list)

EOM
}
while test $# -gt 0; do
    case "$1" in
        '-h') help
              exit 0
              ;;
        '-v') VERB=2
              ;;
        '-l') LIMIT=2
              UUID='abcdabcd-abcd-abcd-abcd-abcdabcdabcd'
              ;;
        '-s') SHUTDOWNAPP=1
              ;;
        '-x') EXPORTAPP=1
              ;;
        '-a') DUMPAPPS=1
              ;;
        '-t') DUMPTMPL=1
              ;;
        '-vmx') VMX=1
              ;;
        '-e') if test $# -gt 1; then
                  shift
                  EXPORTDIR="$1"
              fi
              ;;
        '-u') if test $# -gt 1; then
                  shift
                  UUID="$1"
              fi
              ;;
        *)    echo "unknown option '$1'" 1>&2
              help
              exit 16
              ;;
    esac
    shift
done
if test ${DUMPAPPS:-0} -eq 0 && test ${DUMPTMPL:-0} -eq 0 && test "${UUID}" = ''; then
    help
    exit 1
fi

#TMP=`mktemp -d`
#echo $TMP
#trap "rm -rf ${TMP}" 0 1 2 3 15
TMP="`pwd`/DATA"
mkdir -p "${TMP}"

get_apps() {
    # Get a list of all applications
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/applications"
}

get_uuids_app() {
    # Get a list of all applications
    get_apps | jq '.[].uuid' | tr -d '"'
}

get_fields_app() {
    UUID="$1"
    fields="datacenterUuid,description,memory,name,vcpus"  ## << vcpus, not cpu
    case "$2" in
        '-a') select='';;
        '-m') select="?fields=${fields}";;
        '')   select="?fields=${fields}";;
        *)    select="?fields=$2";;
    esac
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/applications/${UUID}${select}"
}

get_templates() {
    # Get a list of all templates
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/templates"
}

get_uuids_template() {
    # Get a list of all templates
    get_templates | jq '.[].uuid' | tr -d '"'
}

get_fields_template() {
    UUID="$1"
    fields="datacenterUuid,description,memory,name,cpu"  ## << cpu, not vcpus
    case "$2" in
        '-a') select='';;
        '-m') select="?fields=${fields}";;
        '')   select="?fields=${fields}";;
        *)    select="?fields=$2";;
    esac
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/templates/${UUID}${select}"
}

get_app_snapshots() {
    UUID="$1"
    NAME="$2"
    name=`sed -e 's/"/%22/g' -e 's/ /%20/g' <<<"${NAME}"` ## FIXME: should be proper urlencoded
    select="?filters=name%3D%3D%22${name}%22"
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/applications/${UUID}/snapshots${select}"
}

app_shutdown() {
    UUID="$1"
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/applications/${UUID}/shutdown"
}

app_export() {
    uuid="$1"
    mkdir -p "${TMP}/app/"
    app="`get_fields_app ${uuid} -a`"
    echo "${app}"| jq . > "${TMP}/app/${uuid}.meta"
    # export app to template
    _loc=`jq .datacenterUuid <<<"${app}" |tr -d '"'`
    _name=`jq .name <<<"${app}" |tr -d '"'`
    _desc=`jq .description <<<"${app}" |tr -d '"'`
    _vcpu=`jq .vcpus <<<"${app}" |tr -d '"'`
    _vmem=`jq .memory <<<"${app}" |tr -d '"'`
    _boot=`jq .bootOrder <<<"${app}" |sed -e 's/"/\\"/g'`
    ts="`date -uIm|tr -d ':+'`"
    cat > "${TMP}/app/${uuid}.cmd.sh" <<EOM
#!/bin/sh -x

curl -s -H "Authorization: Bearer ${API_TOKEN}" \
     -H "accept: application/json" \
     -X POST "${API_ENDPOINT}/templates" \
     -H "Content-Type: application/json" \
     -d "{ \"applicationUuid\": \"${uuid}\",
           \"datacenterUuid\": \"${_loc}\",
           \"runSysPrep\": true, \"customWindowsSysprepXml\": \"\",
           \"name\": \"${_name} - EXPORT ${ts}\", \"description\": \"${_desc}\",
           \"memory\": ${_vmem}, \"vcpus\": ${_vcpu}, \"bootOrder\": ${_boot},
           \"vmMode\": \"Compatibility\" }" \
| jq . | tee "${TMP}/app/${uuid}.result"
EOM
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X POST "${API_ENDPOINT}/templates" \
         -H "Content-Type: application/json" \
         -d "{ \"applicationUuid\": \"${uuid}\", \"datacenterUuid\": \"${_loc}\", \"runSysPrep\": true, \"customWindowsSysprepXml\": \"\", \"name\": \"${_name} - EXPORT ${ts}\", \"description\": \"${_desc}\", \"memory\": ${_vmem}, \"vcpus\": ${_vcpu}, \"bootOrder\": ${_boot}, \"vmMode\": \"Compatibility\" }" \
      | jq . | tee "${TMP}/app/${uuid}.result"
    action=`cat "${TMP}/app/${uuid}.result"`
    res=`action_wait "${action}"`
    echo "RES = $res"
    for tuuid in `get_uuids_template`; do
        tmpl=`get_fields_template "${tuuid}" -a`
        tname=`jq .name <<<"${tmpl}"|tr -d '"'`
        if test "${tname}" = "${_name} - EXPORT ${ts}"; then
            jq . <<<"${tmpl}" > "${TMP}/app/${uuid}.template.meta"
            bootorder=`jq .[].bootOrder <"${TMP}/app/${uuid}.template.meta"`
            diskuuids=`jq .[].diskUuid <<<"${bootorder}" |tr -d '"'|grep -v null` 
            echo "${diskuuids}" > "${TMP}/app/${uuid}.diskuuids"
            return
        fi
    done
}

app_snapshot() {
    test $# -eq 2 || return 1
    UUID="$1"
    NAME="$2"
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X POST "${API_ENDPOINT}/applications/${UUID}/snapshots" \
         -H "Content-Type: application/json" \
         -d "{ \"name\": \"${NAME}\" }" \
      | jq . | tee "${TMP}/app/${UUID}.snapshot_result"
}

action_wait() {
    ACTION="$1"
    test "${ACTION}" = '' && return
    _act_uuid=`jq .actionUuid <<<"${ACTION}"| tr -d '"'`
    test "${_act_uuid}" = 'null' && return
    mkdir -p "${TMP}/actions"
    _obj_uuid=`jq .objectUuid <<<"${ACTION}"| tr -d '"'`
    _msg=`jq .message <<<"${ACTION}"| tr -d '"'`
    # wait for action to finish (or time out)
    status='Pending'
    cnt=1
    while test "${status}" != "Completed" && test ${cnt:-0} -lt 10; do
        curl -s -w '\nHTTP_code: %{http_code}' \
             -H "Authorization: Bearer ${API_TOKEN}" \
             -H "accept: application/json" \
             -X GET "${API_ENDPOINT}/actions/${_act_uuid}" \
          > "${TMP}/actions/${_act_uuid}"
        code=`grep '^HTTP_CODE:' "${TMP}/actions/${_act_uuid}"|cut -d\  -f2`
        case "`jq .status <"${TMP}/actions/${_act_uuid}" 2>/dev/null|tr -d '\"'`" in
            Completed|completed)
                status='Completed'
                ;;
            *)  case "${code}" in
                    2*) status='Completed';;
                    *)  ;;
                esac
                ;;
        esac
        cnt=`expr $cnt + 1`
    done
    echo $status $_obj_uuid
}

meta2vmx() {
    meta="$1"
    uuid=`jq .uuid <<<"${meta}"|tr -d '"'`
    name=`jq .name <<<"${meta}"|tr -d '"'`
    desc=`jq .descripton <<<"${meta}"|tr -d '"'`
    vcpu=`jq .cpu <<<"${meta}"|tr -d '"'`
    vmem=`jq .memory <<<"${meta}"|tr -d '"'`
    vos=`jq .operatingSystem <<<"${meta}"`
    xmem=`expr ${vmem} / 1024 / 1024`  ## Byte to MB
    ## OS hell
    xosmajor=`jq .type <<<"${vos}"|tr -d '"'`
    xosminor=`jq .version <<<"${vos}"|tr -d '"'`
    ### http://sanbarrow.com/vmx/vmx-guestos.html
    case "${xosmajor}" in
        Windows)
            case "${xosminor}" in
                'Windows server 2016'*) xos='windows9Server-64';;
                'Windows server 201'*)  xos='windows8srv-64';;
                'Windows server 2008'*) xos='winServer2008Enterprise-64';;
                *)  ;;
            esac
            ;;
    esac
    cat > ${EXPORTDIR}/${uuid}.vmx <<EOM
EOM
}


if test ${SHUTDOWNAPP:-0} -eq 1; then
    for uuid in `tr ',' ' ' <<<"$UUID"`; do
        echo "shutting down ${uuid}"
        if test ${FORCE_SHUTDOWN:-0} -eq 0; then
            echo -n 'continue [y/N]? '
            read yn
            case "$yn" in
                yes|y|Y|Yes)
                    echo "ok"
                    res=`app_shutdown "${uuid}"`
                    action_wait "$res"
		    ;;
                *)  echo 'shutdown aborted!' 1>&2
		    ;;
            esac
        fi
    done
fi
if test ${DUMPAPPS:-0} -eq 1; then
    # Get a list of all applications
    get_apps | jq . > "${TMP}/app.json"
    get_uuids_app > "${TMP}/app.uuids"
    mkdir -p "${TMP}/app/"
    for uuid in `cat "${TMP}/app.uuids"`; do
        app="`get_fields_app ${uuid}`"
        echo "${app}"| jq . > "${TMP}/app/${uuid}.meta"
        n=`jq .name <<<"${app}" |tr -d '"'`
        ok=1
        if test ${LIMIT:-1} -gt 0; then
            case "$n" in
                AD*) ok=1;;
                *)   ok=0;;
            esac
        fi
        if test ${ok:-0} -gt 0; then
            ts="`date -uIm|tr -d ':+'`"
            res=`app_snapshot "${uuid}" "$n - SNAP $ts"`
            action_wait "$res"
            ## # export app to template
            ## app_export "${UUID}" "$n" "$c" "$m" "$d" "$l"
        fi
    done
elif test ${DUMPTMPL:-0} -eq 1; then
    # Get a list of all templates
    get_templates | jq . > "${TMP}/templates.json"
    get_uuids_template > "${TMP}/templates.uuids"
    mkdir -p "${TMP}/templates"
    for uuid in `cat "${TMP}/templates.uuids"`; do
        get_fields_template "${uuid}" -a | jq . > "${TMP}/templates/${uuid}.meta"
    done
fi
if test "${UUID}" != ''; then
    uuid="${UUID}"
    if get_uuids_app | grep "${uuid}"; then
        app_export "${uuid}"
        diskuuids=`cat ${TMP}/app/${uuid}.diskuuids`
        if test -d /templates; then
            for diskuuid in ${diskuuids}; do
                ### convert template to VMDK
                test -f /templates/${diskuuid}.qcow2 && \
                    stat /templates/${diskuuid}.qcow2
                #   /usr/bin/qemu-img convert -f qcow2 -O vmdk -o adapter_type=lsilogic,subformat=streamOptimized \
                #     /templates/${diskuuid}.qcow2 \
                #     ${EXPORTDIR}/${diskuuid}.vmdk
            done
        fi
    fi
fi

find "${TMP}"
exit

