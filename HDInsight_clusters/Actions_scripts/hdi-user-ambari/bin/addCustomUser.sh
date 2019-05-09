#!/bin/bash

usage ()
{
    echo "
##########################################
Execution of the Script Action for the creation of a User Ambari.
Usage: addCustomUser.sh <URL_WASB_LOGS> <TARGET_USER> <TARGET_PASSWORD> [options]

Parameters:
  URL_WASB_LOGS      - URL of the WASB directory where additional logs are stored. (ex: 'wasbs://logs@stabdte2d0hdi.blob.core.windows.net').
  TARGET_USER        - Name of the user Ambari to create (ex: 'SPAPPLIBDTHDIDEV').
  TARGET_PASSWORD    - Name of the password Ambari to create.
  
Example:
    ./addCustomUser.sh 'wasbs://logs@stabdte2d0hdi.blob.core.windows.net' 'SPAPPLIBDTHDIDEV' '*********'

##########################################"
    trace_failure_end_processing 132
}

###################################################################
#
# FUNCTIONS
#
###################################################################
trace_rouge()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[91m")$message$(printf "\033[0m")\n"
}

trace_violet()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[95m")$message$(printf "\033[0m")\n"
}

trace_blanc()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") $( echo "${message}" | sed "s/&/\&/g" | sed "s/%/\%%/g" | sed 's#\\#\\\\#g' )" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[97m")$( echo "${message}" | sed "s/&/\&/g" | sed "s/%/\%%/g" | sed 's#\\#\\\\#g' )$(printf "\033[0m")\n"
}

trace_success()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") [   OK   ]  $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[92m")[   OK   ]  $message$(printf "\033[0m")\n"
}

trace_warning()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") [ WARNING ]  $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[93m")[ WARNING ] $message$(printf "\033[0m")\n"
}

trace_failure()
{
    local _message="$1"
    trace_rouge "[  ERROR  ]  $_message"
}

trace_failure_end_processing ()
{
    local _exit_code="$1"
    trace_rouge "[ END ] Stop the load test script"

    if [ "${URL_WASB_LOGS}" != "" ]; then
        trace_violet "=============================================================================="
        trace_violet "Copying the log file ${LOG_FILE} to the WASB"
        trace_violet "=============================================================================="
        pushFileToBlobContainer "${URL_WASB_LOGS}" "${FULL_LOG_FILE}" "logs"
    fi
    
    exit ${_exit_code}
}

get_headnodes() {
    hdfssitepath=/etc/hadoop/conf/hdfs-site.xml
    nn1=$(sed -n '/<name>dfs.namenode.http-address.mycluster.nn1/,/<\/value>/p' $hdfssitepath)
    nn2=$(sed -n '/<name>dfs.namenode.http-address.mycluster.nn2/,/<\/value>/p' $hdfssitepath)

    nn1host=$(sed -n -e 's/.*<value>\(.*\)<\/value>.*/\1/p' <<< $nn1 | cut -d ':' -f 1)
    nn2host=$(sed -n -e 's/.*<value>\(.*\)<\/value>.*/\1/p' <<< $nn2 | cut -d ':' -f 1)

    nn1hostnumber=$(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $nn1host)
    nn2hostnumber=$(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $nn2host)

    #only if both headnode hostnames could be retrieved, hostnames will be returned
    #else nothing is returned
    if [[ ! -z $nn1host && ! -z $nn2host ]]
    then
        if (( $nn1hostnumber < $nn2hostnumber )); then
            echo "$nn1host,$nn2host"
        else
            echo "$nn2host,$nn1host"
        fi
    fi
}

get_primary_headnode() {
    headnodes=`get_headnodes`
    echo "`(echo $headnodes | cut -d ',' -f 1)`"
}

get_primary_headnode_number() {
    primaryhn=`get_primary_headnode`
    echo "`(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $primaryhn)`"
}

checkHostNameAndSetClusterName() {
    fullHostName=$(hostname -f)
    CLUSTER_NAME=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nprint ClusterManifestParser.parse_local_manifest().deployment.cluster_name" | python)

    trace_blanc "fullHostName: ${fullHostName}"
    trace_blanc "CLUSTER_NAME: ${CLUSTER_NAME}"
    if [ $? -ne 0 ]; then
        trace_failure "Cannot determine cluster name. Exiting!"
        trace_failure_end_processing 133
    fi
}

validateUsernameAndPassword() {
    coreSiteContent=$(bash $AMBARICONFIGS_SH -u $AMBARI_ADMIN_USER -p $AMBARI_ADMIN_PASSWORD get $AMBARI_HOST $CLUSTER_NAME core-site)
    if [[ $coreSiteContent == *"[ERROR]"* && $coreSiteContent == *"Bad credentials"* ]]; then
        trace_failure "Username and password are invalid. Cannot connect to Ambari Server. Exiting!"
        trace_failure_end_processing 134
    fi
}

pushFileToBlobContainer()
{
    local _uri_storage_account="$1"
    local _input_file="$2"
    local _output_path="$3"

    inputFileWithoutPath=$(basename ${_input_file})

    hadoop fs -mkdir -p ${_uri_storage_account}/${_output_path}/
    hadoop fs -rmr ${_uri_storage_account}/${_output_path}/${inputFileWithoutPath}
    hadoop fs -copyFromLocal ${_input_file} ${_uri_storage_account}/${_output_path}/
    retcode=$?
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
        trace_blanc "[ OK ] Copy the file ${_input_file} in the directory WASB ${_uri_storage_account}/${_output_path}/"
        trace_blanc " - Command: hadoop fs -copyFromLocal ${_input_file} ${_uri_storage_account}/${_output_path}/"
        trace_blanc " - Return code: ${retcode}"
    else
        trace_blanc "[ ERROR ] Unable to copy the file ${_input_file} in the directory WASB ${_uri_storage_account}/${_output_path}/"
        trace_blanc " - Command: hadoop fs -copyFromLocal ${_input_file} ${_uri_storage_account}/${_output_path}/"
        trace_blanc " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi
}

createUserAmbari()
{
    local _ambari_user_admin="$1"
    local _ambari_password_admin="$2"
    local _ambari_host="$3"
    local _ambari_port="$4"
    local _cluster_name="$5"
    local _ambari_user_to_create="$6"
    local _ambari_password_to_create="$7"

    trace_violet "=============================================================================="
    trace_violet "Creating the User Ambari ${_ambari_user_to_create}"
    trace_violet "=============================================================================="
    curl -u ${_ambari_user_admin}:${_ambari_password_admin} -i -H 'X-Requested-By: ambari' -X POST -d '{"Users/user_name":"'"$_ambari_user_to_create"'","Users/password":"'"$_ambari_password_to_create"'","Users/active":"true","Users/admin":"false"}' http://${_ambari_host}:${_ambari_port}/api/v1/users &>> ${FULL_LOG_FILE}
    retcode=$?
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
        trace_success "Creating the User Ambari ${_ambari_user_to_create} with Ambari Rest API"
        trace_blanc " - Username Admin: ${_ambari_user_admin}"
        trace_blanc " - Password Admin: ************"
        trace_blanc " - Header: -H 'X-Requested-By: ambari'"
        trace_blanc " - Method: POST"
        trace_blanc " - Body: {\"Users/user_name\":\"'\"$_ambari_user_to_create\"'\",\"Users/password\":\"'\"$_ambari_password_to_create\"'\",\"Users/active\":\"true\",\"Users/admin\":\"false\"}"
        trace_blanc " - URL: http://${_ambari_host}:${_ambari_port}/api/v1/users"
        trace_blanc " - Command: curl -u ${_ambari_user_admin}:${_ambari_password_admin} -i -H 'X-Requested-By: ambari' -X POST -d '{\"Users/user_name\":\"'\"$_ambari_user_to_create\"'\",\"Users/password\":\"'\"$_ambari_password_to_create\"'\",\"Users/active\":\"true\",\"Users/admin\":\"false\"}' http://${_ambari_host}:${_ambari_port}/api/v1/users"
        trace_blanc " - Return code: ${retcode}"
    else
        trace_failure "Unable to create the User Ambari ${_ambari_user_to_create} with Ambari Rest API !"
        trace_rouge " - Username Admin: ${_ambari_user_admin}"
        trace_rouge " - Password: ************"
        trace_rouge " - Header: -H 'X-Requested-By: ambari'"
        trace_rouge " - Method: POST"
        trace_rouge " - Body: {\"Users/user_name\":\"'\"$_ambari_user_to_create\"'\",\"Users/password\":\"'\"$_ambari_password_to_create\"'\",\"Users/active\":\"true\",\"Users/admin\":\"false\"}"
        trace_rouge " - URL: http://${_ambari_host}:${_ambari_port}/api/v1/users"
        trace_rouge " - Command: curl -u ${_ambari_user_admin}:${_ambari_password_admin} -i -H 'X-Requested-By: ambari' -X POST -d '{\"Users/user_name\":\"'\"$_ambari_user_to_create\"'\",\"Users/password\":\"'\"$_ambari_password_to_create\"'\",\"Users/active\":\"true\",\"Users/admin\":\"false\"}' http://${_ambari_host}:${_ambari_port}/api/v1/users"
        trace_rouge " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi

    trace_violet "=============================================================================="
    trace_violet "Setting the privileges of the User Ambari ${_ambari_user_to_create}"
    trace_violet "=============================================================================="
    curl -u ${_ambari_user_admin}:${_ambari_password_admin} -i -H 'X-Requested-By: ambari' -X POST -d '[{"PrivilegeInfo":{"permission_name":"SERVICE.OPERATOR","principal_name":"'"$_ambari_user_to_create"'","principal_type":"USER"}}]' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/privileges &>> ${FULL_LOG_FILE}
    retcode=$?
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
        trace_success "Setting the privileges of the User Ambari ${_ambari_user_to_create} with Ambari Rest API"
        trace_blanc " - Username Admin: ${_ambari_user_admin}"
        trace_blanc " - Password Admin: ************"
        trace_blanc " - Header: -H 'X-Requested-By: ambari'"
        trace_blanc " - Method: POST"
        trace_blanc " - Body: [{\"PrivilegeInfo\":{\"permission_name\":\"SERVICE.OPERATOR\",\"principal_name\":\"'\"$_ambari_user_to_create\"'\",\"principal_type\":\"USER\"}}]"
        trace_blanc " - URL: /api/v1/clusters/${_cluster_name}/privileges"
        trace_blanc " - Command: curl -u ${_ambari_user_admin}:${_ambari_password_admin} -i -H 'X-Requested-By: ambari' -X POST -d '{\"Users/user_name\":\"'\"$_ambari_user_to_create\"'\",\"Users/password\":\"'\"$_ambari_password_to_create\"'\",\"Users/active\":\"true\",\"Users/admin\":\"false\"}' http://${_ambari_host}:${_ambari_port}/api/v1/users"
        trace_blanc " - Return code: ${retcode}"
    else
        trace_failure "Unable to set the privileges of the User Ambari ${_ambari_user_to_create} with Ambari Rest API !"
        trace_rouge " - Username Admin: ${_ambari_user_admin}"
        trace_rouge " - Password: ************"
        trace_rouge " - Header: -H 'X-Requested-By: ambari'"
        trace_rouge " - Method: POST"
        trace_rouge " - Body: [{\"PrivilegeInfo\":{\"permission_name\":\"SERVICE.OPERATOR\",\"principal_name\":\"'\"$_ambari_user_to_create\"'\",\"principal_type\":\"USER\"}}]"
        trace_rouge " - URL: /api/v1/clusters/${_cluster_name}/privileges"
        trace_rouge " - Command: curl -u ${_ambari_user_admin}:${_ambari_password_admin} -i -H 'X-Requested-By: ambari' -X POST -d '[{\"PrivilegeInfo\":{\"permission_name\":\"SERVICE.OPERATOR\",\"principal_name\":\"'\"$_ambari_user_to_create\"'\",\"principal_type\":\"USER\"}}]' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/privileges"
        trace_rouge " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi
}

###################################################################
#
# GLOBAL VARIABLES
#
###################################################################
CURRENT_PATH=$( dirname $(readlink -f $0) )
DATE_EXECUTION=$(date '+%Y%m%d-%H%M%S')
SCRIPT_NAME=$(readlink -f $0)

LOG_FILE="${DATE_EXECUTION}_Execute_Scrips_Actions_Create_User_Ambari.log"
FULL_LOG_FILE="/tmp/${LOG_FILE}"
rm -f ${FULL_LOG_FILE}

### Ambari
AMBARI_HOST=headnodehost
AMBARI_PORT=8080
AMBARICONFIGS_PYTHON=/var/lib/ambari-server/resources/scripts/configs.py
AMBARICONFIGS_SH=/var/lib/ambari-server/resources/scripts/configs.sh

###################################################################
#
# BEGIN
#
###################################################################
trace_blanc "[ BEGIN ] Executing the script ${SCRIPT_NAME}"

trace_violet "=============================================================================="
trace_violet "Variables"
trace_violet "=============================================================================="
trace_blanc "SCRIPT_NAME: ${SCRIPT_NAME}"
trace_blanc "LOG_FILE: ${LOG_FILE}"
trace_blanc "FULL_LOG_FILE: ${FULL_LOG_FILE}"

# Check if the user is root
if [ "$(id -u)" != "0" ]; then
   trace_failure "The script has to be run as root."
   usage
fi

# Get the Username and password for the authentification
AMBARI_ADMIN_USER=$(echo -e "import hdinsight_common.Constants as Constants\nprint Constants.AMBARI_WATCHDOG_USERNAME" | python)
AMBARI_ADMIN_PASSWORD=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nimport hdinsight_common.Constants as Constants\nimport base64\nbase64pwd = ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password\nprint base64.b64decode(base64pwd)" | python)

trace_blanc "AMBARI_HOST: ${AMBARI_HOST}"
trace_blanc "AMBARI_PORT: ${AMBARI_PORT}"
trace_blanc "AMBARI_ADMIN_USER: ${AMBARI_ADMIN_USER}"
trace_blanc "AMBARICONFIGS_PYTHON: ${AMBARICONFIGS_PYTHON}"
trace_blanc "AMBARICONFIGS_SH: ${AMBARICONFIGS_SH}"

trace_violet "=============================================================================="
trace_violet "Parameters"
trace_violet "=============================================================================="
URL_WASB_LOGS=$1
TARGET_USER=$2
TARGET_PASSWORD=$3

if [ -z "${TARGET_USER}" ]; then
    echo "[  ERROR  ]  The parameter TARGET_USER is missing. Exiting!"
    usage
fi
if [ -z "${TARGET_PASSWORD}" ]; then
    echo "[  ERROR  ]  The parameter TARGET_PASSWORD is missing. Exiting!"
    usage
fi

trace_blanc "TARGET_USER: ${TARGET_USER}"
trace_blanc "TARGET_PASSWORD: ${TARGET_PASSWORD}"

# Check the parameters
checkHostNameAndSetClusterName
validateUsernameAndPassword

trace_violet "=============================================================================="
trace_violet "Get Head Node"
trace_violet "=============================================================================="
HOSTNAME=$(hostname -f)
PRIMARYHEADNODE=`get_primary_headnode`

trace_blanc "HOSTNAME: ${HOSTNAME}"
trace_blanc "PRIMARYHEADNODE: ${PRIMARYHEADNODE}"

if [[ $HOSTNAME == $PRIMARYHEADNODE ]];then
    # Create the User Ambari
    createUserAmbari "${AMBARI_ADMIN_USER}" "${AMBARI_ADMIN_PASSWORD}" "${AMBARI_HOST}" "${AMBARI_PORT}" "${CLUSTER_NAME}" "${TARGET_USER}" "${TARGET_PASSWORD}"

    trace_blanc "=============================================================================="
    trace_blanc "Copying the log file ${FULL_LOG_FILE} to the WASB"
    trace_blanc "=============================================================================="
    pushFileToBlobContainer "${URL_WASB_LOGS}" "${FULL_LOG_FILE}" "logs"
fi

exit 0