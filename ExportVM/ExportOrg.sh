#!/bin/bash -f

#------------------------------------------------------#
## Documentation:
## https://api.example.com/swagger-ui.html
#------------------------------------------------------#

test "$1" = '-D' && set -x && shift

if test -f '.export.cfg';
    then source .export.cfg
    else echo "API config missing"1>&2
         exit 1
fi
DUMPALL=1


TMP=`mktemp -d`
echo $TMP
#trap "rm -rf $TMP" 0 1 2 3 15


get_app_uuids() {
    # Get a list of all applications
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/applications" \
    | jq '.[].uuid' | tr -d '"'
}

get_app_fields() {
    UUID="$1"
    fields="datacenterUuid,description,memory,name,vcpus"
    curl -s -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X GET "${API_ENDPOINT}/applications/${UUID}?fields=${fields}"
}

export_app() {
    test $# -eq 6 || return 1
    UUID="$1"
    NAME="$2"
    VCPU="$3"
    VMEM="$4"
    DESC="$5"
    DC="$6"
    echo "{ \"applicationUuid\": \"${UUID}\",
            \"bootOrder\": [
              { \"diskUuid\": \"string\",
                \"name\": \"string\",
                \"order\": 1,
                \"vnicUuid\": \"string\"    }  ],
            \"customWindowsSysprepXml\": \"\",
            \"datacenterUuid\": \"${DC}\",
            \"description\": \"${DESC}\",
            \"memory\": ${VMEM},
            \"name\": \"${NAME}\",
            \"runSysPrep\": true,
            \"vcpus\": ${VCPU},
            \"vmMode\": \"Compatibility\" }" \
    | jq . > ${TMP}/${UUID}/state
    cat > ${TMP}/${UUID}/cmd.sh <<EOM
#!/bin/sh -x

curl -H "Authorization: Bearer ${API_TOKEN}" \
     -H "accept: application/json" \
     -X POST "${API_ENDPOINT}/templates" \
     -H "Content-Type: application/json" \
     -d "{ \"applicationUuid\": \"${UUID}\",
           \"bootOrder\": [
             { \"diskUuid\": \"string\",
               \"name\": \"Disk 0\",
               \"order\": 1,
               \"vnicUuid\": null }  ],
           \"customWindowsSysprepXml\": \"\",
           \"datacenterUuid\": \"${DC}\",
           \"description\": \"${DESC}\",
           \"memory\": ${VMEM},
           \"name\": \"${NAME}\",
           \"runSysPrep\": true,
           \"vcpus\": ${VCPU},
           \"vmMode\": \"Compatibility\" }" \
| jq . | tee ${TMP}/${UUID}/result
EOM
    chmod 755 ${TMP}/${UUID}/cmd.sh
return 0
    _act_uuid=`jq .actionUuid < ${TMP}/.state.${UUID}`
    _obj_uuid=`jq .objectUuid < ${TMP}/.state.${UUID}`
    # wait for action to finish (or time out)
    status='started'
    while test "${status}" != "completed"; do
      curl -s -H "Authorization: Bearer ${API_TOKEN}" \
           -H "accept: application/json" \
           -X GET "${API_ENDPOINT}/actions/${_act_uuid}" \
           > ${TMP}/.act.${_act_uuid}
      status=`jq .status < ${TMP}/.act.${_act_uuid}`
    done
}

snapshot_app() {
    test $# -eq 6 || return 1
    UUID="$1"
    NAME="$2"
    curl -H "Authorization: Bearer ${API_TOKEN}" \
         -H "accept: application/json" \
         -X POST "${API_ENDPOINT}/applications/${UUID}/snapshots" \
         -H "Content-Type: application/json" \
         -d "{ \"name\": \"${NAME}\" }" \
      | jq . | tee ${TMP}/${UUID}/snapshot_result
}

action_wait() {
    ACTION="$1"
    _act_uuid=`jq .actionUuid < ${ACTION}`
    _obj_uuid=`jq .objectUuid < ${ACTION}`
    _msg=`jq .message < ${ACTION}`
    # wait for action to finish (or time out)
    status='started'
    cnt=1
    while test "${status}" != "completed" && test ${cnt:-0} -lt 10; do
      curl -s -H "Authorization: Bearer ${API_TOKEN}" \
           -H "accept: application/json" \
           -X GET "${API_ENDPOINT}/actions/${_act_uuid}" \
        | tee ${TMP}/.act.${_act_uuid}
      status=`jq .status < ${TMP}/.act.${_act_uuid}`
      cnt=`expr $cnt + 1`
    done
    echo $status
}


if test ${DUMPALL:-1} -eq 1; then
    # Get a list of all applications
    get_app_uuids > ${TMP}/app.uuids
    for UUID in `cat ${TMP}/app.uuids`; do
        mkdir -p ${TMP}/${UUID}
        APP="`get_app_fields ${UUID}`"
        echo "${APP}"| jq . > ${TMP}/${UUID}/app
        n=`jq .name <<<"${APP}" |tr -d '"'`
        res=`snapshot_app "${UUID}" "$n - SNAP"`
        action_wait "$res"
        ## # export app to template
        ## n=`jq .name <<<"${APP}" |tr -d '"'`
        ## c=`jq .vcpus <<<"${APP}" |tr -d '"'`
        ## m=`jq .memory <<<"${APP}" |tr -d '"'`
        ## d=`jq .description <<<"${APP}" |tr -d '"'`
        ## l=`jq .datacenterUuid <<<"${APP}" |tr -d '"'`
        ## export_app "${UUID}" "$n" "$c" "$m" "$d" "$l"
    done
    echo $TMP
fi

exit


########
cd /templates
uuid=abcdabcd-abcd-abcd-abcd-abcdabcdabcd
snap=`tr -d '-' <<<"$uuid"`
### convert snapshot to template file
/usr/bin/qemu-img convert -O qcow2 /dev/mapper/SNAPSHOT_${snap} /templates/${uuid}.qcow2
### convert template to VMDK
/usr/bin/qemu-img convert -f qcow2 -O vmdk -o adapter_type=lsilogic,subformat=streamOptimized,compat6 ${uuid}.qcow2 ${uuid}.vmdk


