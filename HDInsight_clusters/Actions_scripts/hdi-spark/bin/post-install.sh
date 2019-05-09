#! /bin/bash

usage ()
{
    echo "
##########################################
Configuration of some properties of Spark.
Usage: sudo post-install.sh <LIBS_WASB_DIR> <LOGS_WASB_DIR> <INSTRUMENTATION_KEY> <LIBS_WASB_SAS_TOKEN> [options]

Parameters:
  LIBS_WASB_DIR			- Mandatory WASB directory where additional jars are stored. This directory has to be accessible from the cluster.
  LOGS_WASB_DIR			- Mandatory WASB directory where additional logs are stored. This directory has to be accessible from the cluster.
  INSTRUMENTATION_KEY	- Instrumentation Key of the ApplicationInsight.
  LIBS_WASB_SAS_TOKEN	- SAS Token to access to the Blob Container.
  
Example:
    ./post-install.sh https://staomee2r.blob.core.windows.net/packages/hdi-spark wasb://libs@staomee2rhdi.blob.core.windows.net afa93915-e54b-4975-8201-549cc449dca5 ?st=2018-06-07T14%3A07%3A16Z&se=2018-06-08T14%3A07%3A16Z&sp=rwl&sv=2017-07-29&sr=c&sig=TUBmR9i7rbnORgTECoWuBXZ%2BgwCghv5YhzaNv4XQtdI%3D

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
    echo "$(date +"%Y-%m-%d %H:%M:%S") [ WARNING ] $message" >> ${FULL_LOG_FILE}
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

    if [ "${LOGS_WASB_DIR}" != "" ]; then
        trace_violet "=============================================================================="
        trace_violet "Copying the log file ${LOG_FILE} to the WASB"
        trace_violet "=============================================================================="
        hadoop fs -mkdir -p ${LOGS_WASB_DIR}/logs/
        hadoop fs -rmr ${LOGS_WASB_DIR}/logs/${LOG_FILE}
        hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/
        retcode=$?
        if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
            trace_success "Copy the file ${FULL_LOG_FILE} to the directory WASB ${LOGS_WASB_DIR}/logs/"
            trace_blanc " - Command: hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/"
            trace_blanc " - Return code: ${retcode}"
        else
            trace_failure "Unable to copy the file ${FULL_LOG_FILE} to the directory WASB ${LOGS_WASB_DIR}/logs/"
            trace_rouge " - Command: hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/"
            trace_rouge " - Return code: ${retcode}"
        fi
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
    coreSiteContent=$(bash $AMBARICONFIGS_SH -u $AMBARI_USER -p $AMBARI_PASSWORD get $AMBARI_HOST $CLUSTER_NAME core-site)
    if [[ $coreSiteContent == *"[ERROR]"* && $coreSiteContent == *"Bad credentials"* ]]; then
        trace_failure "Username and password are invalid. Cannot connect to Ambari Server. Exiting!"
        trace_failure_end_processing 134
    fi
}

stopServiceViaRest()
{
    local _ambari_user="$1"
    local _ambari_password="$2"
    local _ambari_host="$3"
    local _ambari_port="$4"
    local _cluster_name="$5"
    local _service_name="$6"

    if [ -z "${_service_name}" ]; then
        trace_failure "Need service name to stop service"
        trace_failure_end_processing 137
    fi

    trace_violet "=============================================================================="
    trace_violet "Stopping the service ${_service_name}"
    trace_violet "=============================================================================="
    curl -u ${_ambari_user}:${_ambari_password} -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop Service for updating Spark libraries"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name} &>> ${FULL_LOG_FILE}
    retcode=$?
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
        trace_success "Stopping the service ${_service_name} with Ambari Rest API"
        trace_blanc " - Username: ${_ambari_user}"
        trace_blanc " - Password: ************"
        trace_blanc " - Header: -H 'X-Requested-By: ambari'"
        trace_blanc " - Method: PUT"
        trace_blanc " - Body: {\"RequestInfo\": {\"context\" :\"Stop Service for updating Spark libraries\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}"
        trace_blanc " - URL: http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}"
        trace_blanc " - Command: curl -u ${_ambari_user}:${_ambari_password} -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Stop Service for updating Spark libraries\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}"
        trace_blanc " - Return code: ${retcode}"
    else
        trace_failure "Unable to stop the service ${_service_name} with Ambari Rest API !"
        trace_rouge " - Username: ${_ambari_user}"
        trace_rouge " - Password: ************"
        trace_rouge " - Header: -H 'X-Requested-By: ambari'"
        trace_rouge " - Method: PUT"
        trace_rouge " - Body: {\"RequestInfo\": {\"context\" :\"Stop Service for updating Spark libraries\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}"
        trace_rouge " - URL: http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}"
        trace_rouge " - Command: curl -u ${_ambari_user}:${_ambari_password} -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Stop Service for updating Spark libraries\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}"
        trace_rouge " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi
}

startServiceViaRest()
{
    local _ambari_user="$1"
    local _ambari_password="$2"
    local _ambari_host="$3"
    local _ambari_port="$4"
    local _cluster_name="$5"
    local _service_name="$6"

    if [ -z "${_service_name}" ]; then
        trace_failure "Need service name to start service"
        trace_failure_end_processing 138
    fi
    sleep 2

    trace_violet "=============================================================================="
    trace_violet "Starting the service ${_service_name} using a background process"
    trace_violet "=============================================================================="
    nohup bash -c "sleep 90; curl -u ${_ambari_user}:'${_ambari_password}' -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Start Service ${_service_name}\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}" > /tmp/Start${_service_name}.out 2> /tmp/Start${_service_name}.err < /dev/null &
    retcode=$?
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
        trace_success "Starting the service ${_service_name} with Ambari Rest API"
        trace_blanc " - Username: ${_ambari_user}"
        trace_blanc " - Password: ************"
        trace_blanc " - Header: -H 'X-Requested-By: ambari'"
        trace_blanc " - Method: PUT"
        trace_blanc " - Body: {\"RequestInfo\": {\"context\" :\"Stop Service ${_service_name}\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}"
        trace_blanc " - URL: http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}"
        trace_blanc " - Command: nohup bash -c \"sleep 90; curl -u ${_ambari_user}:'${_ambari_password}' -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Start Service ${_service_name}\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}\" > /tmp/Start${_service_name}.out 2> /tmp/Start${_service_name}.err < /dev/null &"
        trace_blanc " - Return code: ${retcode}"
    else
        trace_failure "Unable to start the service ${_service_name} with Ambari Rest API !"
        trace_rouge " - Username: ${_ambari_user}"
        trace_rouge " - Password: ************"
        trace_rouge " - Header: -H 'X-Requested-By: ambari'"
        trace_rouge " - Method: PUT"
        trace_rouge " - Body: {\"RequestInfo\": {\"context\" :\"Stop Service ${_service_name}\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}"
        trace_rouge " - URL: http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}"
        trace_rouge " - Command: nohup bash -c \"sleep 90; curl -u ${_ambari_user}:'${_ambari_password}' -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Start Service ${_service_name}\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}' http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/services/${_service_name}\" > /tmp/Start${_service_name}.out 2> /tmp/Start${_service_name}.err < /dev/null &"
        trace_rouge " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi
}

setConfigTypeAmbariFromFile() 
{
    local _ambari_configs_script_python="$1"
    local _ambari_user="$2"
    local _ambari_password="$3"
    local _ambari_port="$4"
    local _ambari_host="$5"
    local _cluster_name="$6"
    local _config_type="$7"
    local _file="$8"

    # Set the configuration of the type "spark2-log4j-properties"
    sed -i -e 's/\r//g' ${_file}
    python ${_ambari_configs_script_python} --user=${_ambari_user} --password=${_ambari_password} --port=${_ambari_port} --action=set --host=${_ambari_host} --cluster=${_cluster_name} --config-type=${_config_type} --file=${_file} &>> ${FULL_LOG_FILE}
    retcode=$?
    if [ $retcode -eq 0 ]; then
        trace_success "Set the config type \"${_config_type}\" from the JSON file ${_file}"
        trace_blanc " - File: ${_file}"
        sed -i -e 's/\r//g' ${_file}
        cat ${_file}
        cat ${_file} >> ${FULL_LOG_FILE}
        trace_blanc "Command: python ${_ambari_configs_script_python} --user=${_ambari_user} --password=${_ambari_password} --port=${_ambari_port} --action=set --host=${_ambari_host} --cluster=${_cluster_name} --config-type=${_config_type} --file=${_file}"
    else
        trace_failure "Unable to set the config type \"${_config_type}\" from the JSON file ${_file} !"
        trace_blanc " - File: ${_file}"
        sed -i -e 's/\r//g' ${_file}
        cat ${_file}
        cat ${_file} >> ${FULL_LOG_FILE}
        trace_rouge "Command: python ${_ambari_configs_script_python} --user=${_ambari_user} --password=${_ambari_password} --port=${_ambari_port} --action=set --host=${_ambari_host} --cluster=${_cluster_name} --config-type=${_config_type} --file=${_file}"
        trace_failure_end_processing 139
    fi
}

setConfigTypeAmbariFromKeyValue()
{
    local _ambari_configs_script_python="$1"
    local _ambari_user="$2"
    local _ambari_password="$3"
    local _ambari_port="$4"
    local _ambari_host="$5"
    local _cluster_name="$6"
    local _config_type="$7"
    local _key="$8"
    local _value="$9"

    python ${_ambari_configs_script_python} --user=${_ambari_user} --password=${_ambari_password} --port=${_ambari_port} --action=set --host=${_ambari_host} --cluster=${_cluster_name} --config-type=${_config_type} --key="${_key}" --value="${_value}" &>> ${FULL_LOG_FILE}
    retcode=$?
    if [ $retcode -eq 0 ]; then
        trace_success "Setting Spark with Ambari Rest API"
        trace_blanc " - Config type: ${_config_type}"
        trace_blanc " - Key: ${_key}"
        trace_blanc " - Value: ${_value}"
        trace_blanc " - Command: python ${_ambari_configs_script_python} --user=${_ambari_user} --password=${_ambari_password} --port=${_ambari_port} --action=set --host=${_ambari_host} --cluster=${_cluster_name} --config-type=${_config_type} --key=\"${_key}\" --value=\"${_value}\""
    else
        trace_failure "Unable to setting Spark with Ambari Rest API !"
        trace_rouge " - Config type: ${_config_type}"
        trace_rouge " - Key: ${_key}"
        trace_rouge " - Value: ${_value}"
        trace_rouge " - Command: python ${_ambari_configs_script_python} --user=${_ambari_user} --password=${_ambari_password} --port=${_ambari_port} --action=set --host=${_ambari_host} --cluster=${_cluster_name} --config-type=${_config_type} --key=\"${_key}\" --value=\"${_value}\""
        trace_rouge " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi
}

pushFileToBlobContainer()
{
    local _uri_blob_container="$1"
    local _blob_container_file_path="$2"
    local _file_name="$3"
    local _sas_token="$4"
    
    file_name_without_path="$(basename ${_file_name})"
    uri_blob="${_uri_blob_container}${_blob_container_file_path}"
    full_uri_blob_with_sas_token="${uri_blob}/${file_name_without_path}${_sas_token}"

    http_code=$( curl -k -f -H "x-ms-date: $(date -I)" -H "x-ms-blob-type: BlockBlob" --silent --write-out "%{http_code}\n" -X PUT "${full_uri_blob_with_sas_token}" --data-binary @${_file_name} )
    if [ "${http_code}" = "201" ]; then
        trace_success "Push the file ${_file_name} to the Blob Container ${uri_blob}/"
        trace_blanc " - URI Blob Container: ${_uri_blob_container}"
        trace_blanc " - Blob Container File Path: ${_blob_container_file_path}"
        trace_blanc " - File Name: ${_file_name}"
        trace_blanc " - SAS Token: ${_sas_token}"
        trace_blanc " - Command: curl -k -f -H \"x-ms-date: $(date -I)\" -H \"x-ms-blob-type: BlockBlob\" --silent --write-out \"%{http_code}\n\" -X PUT \"${full_uri_blob_with_sas_token}\" --data-binary @${_file_name}"
        trace_blanc " - HTTP code: ${http_code}"
    else
        trace_failure "Unable to pushing the file ${_file_name} to the Blob Container ${uri_blob}/ !"
        trace_blanc " - URI Blob Container: ${_uri_blob_container}"
        trace_blanc " - Blob Container File Path: ${_blob_container_file_path}"
        trace_blanc " - File Name: ${_file_name}"
        trace_blanc " - SAS Token: ${_sas_token}"
        trace_blanc " - Command: curl -k -f -H \"x-ms-date: $(date -I)\" -H \"x-ms-blob-type: BlockBlob\" --silent --write-out \"%{http_code}\n\" -X PUT \"${full_uri_blob_with_sas_token}\" --data-binary @${_file_name}"
        trace_rouge " - HTTP code: ${http_code}"
        trace_rouge "[ END ] Stop the the script ${SCRIPT_NAME}"
        exit 139
    fi
}

getFileFromBlobContainer()
{
    local _uri_blob_container="$1"
    local _blob_container_file_path="$2"
    local _file_name="$3"
    local _sas_token="$4"
    local _output_path="$5"

    file_name_without_path="$(basename ${_file_name})"
    uri_blob="${_uri_blob_container}${_blob_container_file_path}"
    full_uri_blob_with_sas_token="${uri_blob}/${file_name_without_path}${_sas_token}"

    http_code=$( curl -k -f -o "${_output_path}/${file_name_without_path}" --silent --write-out "%{http_code}\n" -X GET "${full_uri_blob_with_sas_token}" )
    if [ "${http_code}" = "200" ]; then
        trace_success "Get the file ${file_name_without_path} from the Blob Container Path ${uri_blob}/"
        trace_blanc " - URI Blob Container: ${_uri_blob_container}"
        trace_blanc " - Blob Container File Path: ${_blob_container_file_path}"
        trace_blanc " - File Name: ${file_name_without_path}"
        trace_blanc " - SAS Token: ${_sas_token}"
        trace_blanc " - Output Path: ${_output_path}"
        trace_blanc " - Command: curl -k -f -o \"${_output_path}/${file_name_without_path}\" --silent --write-out \"%%{http_code}\n\" -X GET \"${full_uri_blob_with_sas_token}\""
        trace_blanc " - HTTP code: ${http_code}"
    else
        trace_failure "Unable to getting the file ${file_name_without_path} from the Blob Container ${uri_blob}/ !"
        trace_blanc " - URI Blob Container: ${_uri_blob_container}"
        trace_blanc " - Blob Container File Path: ${_blob_container_file_path}"
        trace_blanc " - File Name: ${file_name_without_path}"
        trace_blanc " - SAS Token: ${_sas_token}"
        trace_blanc " - Output Path: ${_output_path}"
        trace_blanc " - Command: curl -k -f -o \"${_output_path}/${file_name_without_path}\" --silent --write-out \"%%{http_code}\n\" -X GET \"${full_uri_blob_with_sas_token}\""
        trace_rouge " - HTTP code: ${http_code}"
        trace_rouge "[ END ] Stop the the script ${SCRIPT_NAME}"
        exit 139
    fi
}

###################################################################
#
# GLOBAL VARIABLES
#
###################################################################

export SPARK_HOME=/usr/hdp/current/spark2-client

SPARK_LIBS_JARS=$SPARK_HOME/jars
AMBARI_HOST=headnodehost
AMBARI_PORT=8080
AMBARICONFIGS_PYTHON=/var/lib/ambari-server/resources/scripts/configs.py
AMBARICONFIGS_SH=/var/lib/ambari-server/resources/scripts/configs.sh

CURRENT_PATH=$( dirname $(readlink -f $0) )
DATE_EXECUTION=$(date '+%Y%m%d-%H%M%S')
SCRIPT_NAME=$(readlink -f $0)

LOG_FILE="${DATE_EXECUTION}_Execute_Scrips_Actions_Application_Insights_Libs_$( hostname ).log"
FULL_LOG_FILE="/tmp/${LOG_FILE}"
rm -f ${FULL_LOG_FILE}

###################################################################
#
# BEGIN
#
###################################################################
trace_blanc "[ BEGIN ] Executing the script ${SCRIPT_NAME}"

trace_violet "=============================================================================="
trace_violet "Variables"
trace_violet "=============================================================================="
trace_blanc "SPARK_HOME: ${SPARK_HOME}"
trace_blanc "SPARK_LIBS_JARS: ${SPARK_LIBS_JARS}"
trace_blanc "AMBARI_HOST: ${AMBARI_HOST}"
trace_blanc "AMBARI_PORT: ${AMBARI_PORT}"
trace_blanc "AMBARICONFIGS_PYTHON: ${AMBARICONFIGS_PYTHON}"
trace_blanc "AMBARICONFIGS_SH: ${AMBARICONFIGS_SH}"

# Check if the user is root
if [ "$(id -u)" != "0" ]; then
    trace_failure "The script has to be run as root."
    usage
fi

# Get the Username and password for the authentification
AMBARI_USER=$(echo -e "import hdinsight_common.Constants as Constants\nprint Constants.AMBARI_WATCHDOG_USERNAME" | python)
AMBARI_PASSWORD=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nimport hdinsight_common.Constants as Constants\nimport base64\nbase64pwd = ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password\nprint base64.b64decode(base64pwd)" | python)

trace_blanc "AMBARI_USER: ${AMBARI_USER}"

trace_violet "=============================================================================="
trace_violet "Parameters"
trace_violet "=============================================================================="
# Get the parameters
LIBS_WASB_DIR=$1
LOGS_WASB_DIR=$2
INSTRUMENTATION_KEY=$3
LIBS_WASB_SAS_TOKEN=$4

if [ -z "${LIBS_WASB_DIR}" ]; then
    trace_failure "The parameter LIBS_WASB_DIR is missing. Exiting!"
    usage
fi

if [ -z "${LOGS_WASB_DIR}" ]; then
    trace_failure "The parameter LOGS_WASB_DIR is missing. Exiting!"
    usage
fi

if [ -z "${INSTRUMENTATION_KEY}" ]; then
    trace_failure "The parameter INSTRUMENTATION_KEY is missing. Exiting!"
    usage
fi

if [ -z "${LIBS_WASB_SAS_TOKEN}" ]; then
    trace_failure "The parameter LIBS_WASB_SAS_TOKEN is missing. Exiting!"
    usage
fi

trace_blanc "LIBS_WASB_DIR: ${LIBS_WASB_DIR}"
trace_blanc "LOGS_WASB_DIR: ${LOGS_WASB_DIR}"
trace_blanc "INSTRUMENTATION_KEY: ${INSTRUMENTATION_KEY}"
trace_blanc "LIBS_WASB_SAS_TOKEN: ${LIBS_WASB_SAS_TOKEN}"

# Check the parameters
checkHostNameAndSetClusterName
validateUsernameAndPassword

trace_violet "=============================================================================="
trace_violet "Getting files from the WASB"
trace_violet "=============================================================================="
mkdir -p ${SPARK_LIBS_JARS} &>> ${FULL_LOG_FILE}
retcode=$?
if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
    trace_success "Create the directory ${SPARK_LIBS_JARS}/"
    trace_blanc " - Command: mkdir -p ${SPARK_LIBS_JARS}"
    trace_blanc " - Return code: ${retcode}"
else
    trace_failure "Unable to create the directory ${SPARK_LIBS_JARS}/"
    trace_rouge " - Command: mkdir -p ${SPARK_LIBS_JARS}"
    trace_rouge " - Return code: ${retcode}"
    trace_failure_end_processing 139
fi

# Copy Spark libs
getFileFromBlobContainer "${LIBS_WASB_DIR}" "/jars" "applicationinsights-logging-log4j1_2-2.0.2.jar" "${LIBS_WASB_SAS_TOKEN}" "${SPARK_LIBS_JARS}/"
getFileFromBlobContainer "${LIBS_WASB_DIR}" "/jars" "applicationinsights-web-2.0.2.jar" "${LIBS_WASB_SAS_TOKEN}" "${SPARK_LIBS_JARS}/"
getFileFromBlobContainer "${LIBS_WASB_DIR}" "/jars" "ApplicationInsights.xml" "${LIBS_WASB_SAS_TOKEN}" "${SPARK_LIBS_JARS}/"
sed -i -e 's/\r//g' ${SPARK_LIBS_JARS}/ApplicationInsights.xml

# Copy spark2-log4j.properties
rm -f /tmp/spark2-log4j.properties
getFileFromBlobContainer "${LIBS_WASB_DIR}" "/conf" "spark2-log4j.properties" "${LIBS_WASB_SAS_TOKEN}" "/tmp/"
sed -i -e 's/\r//g' /tmp/spark2-log4j.properties

# Configuration of the Instrumentation Key in the file ${SPARK_LIBS_JARS}/ApplicationInsights.xml
if [ -f "${SPARK_LIBS_JARS}/ApplicationInsights.xml" ]
then
    sed -i -e 's/\r//g' ${SPARK_LIBS_JARS}/ApplicationInsights.xml
    sed -i -e "s/INSTRUMENTATION_KEY/${INSTRUMENTATION_KEY}/g" ${SPARK_LIBS_JARS}/ApplicationInsights.xml
    retcode=$?
    if [ $retcode -eq 0 ]; then
        trace_blanc " - File: ${SPARK_LIBS_JARS}/ApplicationInsights.xml"
        cat ${SPARK_LIBS_JARS}/ApplicationInsights.xml; printf "\n"
        cat ${SPARK_LIBS_JARS}/ApplicationInsights.xml >> ${FULL_LOG_FILE}
        trace_blanc " - Instrumentation Key: ${INSTRUMENTATION_KEY}"
        trace_blanc " - Command: sed -i -e 's/INSTRUMENTATION_KEY/${INSTRUMENTATION_KEY}/g' ${SPARK_LIBS_JARS}/ApplicationInsights.xml"
        trace_blanc " - Return code: ${retcode}"
    else
        trace_failure "Unable to edit the Instrumentation Key in the file ${SPARK_LIBS_JARS}/ApplicationInsights.xml"
        trace_blanc " - File: ${SPARK_LIBS_JARS}/ApplicationInsights.xml"
        cat ${SPARK_LIBS_JARS}/ApplicationInsights.xml; printf "\n"
        cat ${SPARK_LIBS_JARS}/ApplicationInsights.xml >> ${FULL_LOG_FILE}
        trace_rouge " - Instrumentation Key: ${INSTRUMENTATION_KEY}"
        trace_rouge " - Command: sed -i -e 's/INSTRUMENTATION_KEY/${INSTRUMENTATION_KEY}/g' ${SPARK_LIBS_JARS}/ApplicationInsights.xml"
        trace_rouge " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi
else
    trace_failure "The file ${SPARK_LIBS_JARS}/ApplicationInsights.xml does not exists"
    trace_failure_end_processing 139
fi

trace_violet "=============================================================================="
trace_violet "Updating Ambari configs and restarting services from primary headnode"
trace_violet "=============================================================================="
PRIMARYHEADNODE=`get_primary_headnode`
PRIMARY_HN_NUM=`get_primary_headnode_number`

# Check if values retrieved are empty, if yes, exit with error
if [[ -z $PRIMARYHEADNODE ]]; then
    trace_failure "Could not determine primary headnode."
    trace_failure_end_processing 141
fi

if [[ -z "$PRIMARY_HN_NUM" ]]; then
    trace_failure "Could not determine primary headnode number."
    trace_failure_end_processing 142
fi

fullHostName=$( hostname -f )
if [ "${fullHostName,,}" == "${PRIMARYHEADNODE,,}" ]; then
    # Add '\n' at the end of each lines in the file spark2-log4j.properties
    result=$( cat /tmp/spark2-log4j.properties | awk 'BEGIN {RS="\n";ORS="\\n"} {print $0}' )

    # Add '\' to each '"' in the content of the file spark2-log4j.properties
    result=${result//\"/\\\"}

    # Edit the JSON file of the configuration of the file log4j.properties
    rm -f /tmp/spark2_log4j_properties.json
    echo "{ \"properties\": { \"content\": \"${result}\" } }" > /tmp/spark2_log4j_properties.json

    # Set the configuration of the type "spark2-log4j-properties"
    CONFIG_TYPE="spark2-log4j-properties"
    FILE_DATA="/tmp/spark2_log4j_properties.json"
    setConfigTypeAmbariFromFile "${AMBARICONFIGS_PYTHON}" "${AMBARI_USER}" "${AMBARI_PASSWORD}" "${AMBARI_PORT}" "${AMBARI_HOST}" "${CLUSTER_NAME}" "${CONFIG_TYPE}" "${FILE_DATA}"

    # Set the configuration of the type "spark2-defaults"
    CONFIG_TYPE="spark2-defaults"
    KEY="spark.driver.extraJavaOptions"
    VALUE="-Dhdp.version={{hdp_full_version}} -Detwlogger.component=sparkdriver -DlogFilter.filename=SparkLogFilters.xml -DpatternGroup.filename=SparkPatternGroups.xml -Dlog4jspark.root.logger=INFO,console,RFA,ETW,Anonymizer -Dlog4jspark.log.dir=/var/log/sparkapp/\${user.name} -Dlog4jspark.log.file=sparkdriver.log -Dlog4j.configuration=file:/usr/hdp/current/spark2-client/conf/log4j.properties -Djavax.xml.parsers.SAXParserFactory=com.sun.org.apache.xerces.internal.jaxp.SAXParserFactoryImpl -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=45 -Dlog4jspark.root.logger=INFO,console,RFA,ETW,Anonymizer,ApplicationInsights"
    setConfigTypeAmbariFromKeyValue "${AMBARICONFIGS_PYTHON}" "${AMBARI_USER}" "${AMBARI_PASSWORD}" "${AMBARI_PORT}" "${AMBARI_HOST}" "${CLUSTER_NAME}" "${CONFIG_TYPE}" "${KEY}" "${VALUE}"

    CONFIG_TYPE="spark2-defaults"
    KEY="spark.executor.extraJavaOptions"
    VALUE="-Dhdp.version={{hdp_full_version}} -Detwlogger.component=sparkexecutor -DlogFilter.filename=SparkLogFilters.xml -DpatternGroup.filename=SparkPatternGroups.xml -Dlog4jspark.root.logger=INFO,console,RFA,ETW,Anonymizer -Dlog4jspark.log.dir=/var/log/sparkapp/\${user.name} -Dlog4jspark.log.file=sparkexecutor.log -Dlog4j.configuration=file:/usr/hdp/current/spark2-client/conf/log4j.properties -Djavax.xml.parsers.SAXParserFactory=com.sun.org.apache.xerces.internal.jaxp.SAXParserFactoryImpl -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=45 -Dlog4jspark.root.logger=INFO,console,RFA,ETW,Anonymizer,ApplicationInsights"
    setConfigTypeAmbariFromKeyValue "${AMBARICONFIGS_PYTHON}" "${AMBARI_USER}" "${AMBARI_PASSWORD}" "${AMBARI_PORT}" "${AMBARI_HOST}" "${CLUSTER_NAME}" "${CONFIG_TYPE}" "${KEY}" "${VALUE}"

    # Remove the files
    rm -f /tmp/spark2-log4j.properties
    rm -f /tmp/spark2_log4j_properties.json

    # Stop the service SPARK2
    stopServiceViaRest "${AMBARI_USER}" "${AMBARI_PASSWORD}" "${AMBARI_HOST}" "${AMBARI_PORT}" "${CLUSTER_NAME}" "SPARK2"

    # Start the service SPARK2
    startServiceViaRest "${AMBARI_USER}" "${AMBARI_PASSWORD}" "${AMBARI_HOST}" "${AMBARI_PORT}" "${CLUSTER_NAME}" "SPARK2"

    trace_violet "=============================================================================="
    trace_violet "Copying the log file ${LOG_FILE} to the WASB"
    trace_violet "=============================================================================="
    hadoop fs -mkdir -p ${LOGS_WASB_DIR}/logs/
    hadoop fs -rmr ${LOGS_WASB_DIR}/logs/${LOG_FILE}
    hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/
    retcode=$?
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
        trace_success "Copy the file ${FULL_LOG_FILE} to the directory WASB ${LOGS_WASB_DIR}/logs/"
        trace_blanc " - Command: hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/"
        trace_blanc " - Return code: ${retcode}"
    else
        trace_failure "Unable to copy the file ${FULL_LOG_FILE} to the directory WASB ${LOGS_WASB_DIR}/logs/"
        trace_rouge " - Command: hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/"
        trace_rouge " - Return code: ${retcode}"
        trace_failure_end_processing 139
    fi
fi

###################################################################
#
# END
#
###################################################################
trace_blanc "[ END ] Executing the script ${SCRIPT_NAME}"

exit 0