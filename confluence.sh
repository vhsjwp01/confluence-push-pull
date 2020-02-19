#!/bin/bash
#set -x

###############################################################################
#                      S C R I P T    D E F I N I T I O N
################################################################################
#

#-------------------------------------------------------------------------------
# Revision History
#-------------------------------------------------------------------------------
# 20150316     Jason W. Plummer          Original: A generic script to push or
#                                        pull attachments from or to confluence
# 20150317     Jason W. Plummer          Added support to process JSON output
#                                        to determine successful push.  Added
#                                        option to overwrite local file before
#                                        a pull of same name
# 20150501     Jason W. Plummer          Added support for versioning of the 
#                                        file being uploaded into confluence.
#                                        Added support for downloading a 
#                                        specific file version
# 20150521     Jason W. Plummer          Added remote pull file detection and
#                                        authentication failure detection

################################################################################
# DESCRIPTION
################################################################################
#

# NAME: confluence.sh
# 
# This script performs a REST API POST or GET of confluence attachment objects
#
# OPTIONS:
#
# --action        - Valid values are "push" or "pull".
#                   This argument is REQUIRED.
# --filename      - The name of the attachment in confluence.
#                   This argument is REQUIRED.
# --pageid        - The parent page identifier in confluence.
#                   This argument is REQUIRED.
# --urlbase       - The confluence base URL to use.
#                   This argument is OPTIONAL.
#                   Defaults to:
#
#                       PUSH:
#                           https://<confluence hostname>/rest/api/content/
#                       PULL:
#                           https://<confluence hostname>/download/attachments/
#
#                   If urlbase is supplied, then it is assumed to be a fully
#                   qualified path to a file for pulling, or a fully qualified
#                   path for pushing, and as such needed data will be mined from
#                   the value (action, filename, pageid).
#
#                   Example 1 (PUSH):
#                       --urlbase https://<confluence hostname>/rest/api/content/<pageid>/child/attachment
#
#                       would be mined to yield:
#                           action=push     - because the url contains the 
#                                             words "rest/api"
#                           pageid=43001610 - because the pageid is the third
#                                             element from the end using IFS=/
#                   Example 2 (PULL):
#                       --urlbase https://<confluence hostname>/download/attachments/<pageid>/C-BPN-TEST.pdf?api=v2
#
#                       would be mined to yield:
#                           action=pull             - because the url contains 
#                                                     the words 
#                                                     "download/attachment"
#                           pageid=43001610         - because the pageid is the
#                                                     second element from the 
#                                                     end using IFS=/
#                           filename=C-BPN-TEST.pdf - because the filename is 
#                                                     the last element from the
#                                                     end using IFS=/, and the 
#                                                     first element of th result
#                                                     using IFS=?
# --username      - The confluence username to use.
#                   This argument is REQUIRED.
# --password      - The confluence password to use with --username.
#                   This argument is OPTIONAL.
#                   The script will prompt for password if not provided

################################################################################
# CONSTANTS
################################################################################
#

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
TERM=vt100
export TERM PATH

SUCCESS=0
ERROR=1
STDOUT_OFFSET="    "

CONFLUENCE_URL="" # URL of your on-prem Atlassian Confluence instance

SCRIPT_NAME="${0}"

USAGE_ENDLINE="\n${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}"
USAGE="${SCRIPT_NAME}${USAGE_ENDLINE}"
USAGE="${USAGE}[ --action <valid values are \"pull\" or \"push\" *REQUIRED*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --filename <the name of a confluence attachment *REQUIRED*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --pageid <the parent page identifier in confluence *REQUIRED*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --urlbase <the confluence base URL *OPTIONAL*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --username <the confluence username to use for authentication *REQUIRED*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --password <the confluence password to use for authentication *OPTIONAL*> ]${USAGE_ENDLINE}"

###############################################################################
# VARIABLES
################################################################################
#

err_msg=""
exit_code=${SUCCESS}

curl_command=""
temp_dir="/tmp/confluence/$$"
temp_file="output.$$"

trap "if [ -d \"${temp_dir}\" ]; then rm -rf \"${temp_dir}\" ; fi" 0 1 2 3 15

################################################################################
# SUBROUTINES
################################################################################
#

# WHAT: Subroutine f__check_command
# WHY:  This subroutine checks the contents of lexically scoped ${1} and then
#       searches ${PATH} for the command.  If found, a variable of the form
#       my_${1} is created.
# NOTE: Lexically scoped ${1} should not be null, otherwise the command for
#       which we are searching is not present via the defined ${PATH} and we
#       should complain
#
f__check_command() {
    return_code=${SUCCESS}
    my_command="${1}"

    if [ "${my_command}" != "" ]; then
        my_command_check=`unalias "${i}" 2> /dev/null ; which "${1}" 2> /dev/null`

        if [ "${my_command_check}" = "" ]; then
            return_code=${ERROR}
        else
            eval my_${my_command}="${my_command_check}"
        fi

    else
        echo "${STDOUT_OFFSET}ERROR:  No command was specified"
        return_code=${ERROR}
    fi

    return ${return_code}
}

#-------------------------------------------------------------------------------

################################################################################
# MAIN
################################################################################
#

# WHAT: Make sure CONFLUENCE_URL is set
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ -z "${CONFLUENCE_URL}" ]; then
        err_msg="Please make sure the variable 'CONFLUENCE_URL' is defined in this script"
        let exit_code=${ERROR}
    fi

fi

# WHAT: Make sure we have some useful commands
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    for command in awk basename curl date egrep jq mkdir rm sed stty ; do
        unalias ${command} > /dev/null 2>&1
        f__check_command "${command}"

        if [ ${?} -ne ${SUCCESS} ]; then
            let exit_code=${exit_code}+1
        fi

    done

fi

# WHAT: Make sure we have necessary arguments
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    while (( "${#}" )); do
        key=`echo "${1}" | ${my_sed} -e 's?\`??g'`
        value=`echo "${2}" | ${my_sed} -e 's?\`??g'`

        case "${key}" in

            --action|--debug|--filename|--pageid|--urlbase|--username|--password)
                key=`echo "${key}" | ${my_sed} -e 's?^--??g'`

                if [ "${value}" != "" ]; then
                    eval ${key}="${value}"
                    shift
                    shift
                else
                    echo "${STDOUT_OFFSET}ERROR:  No value assignment can be made for command line argument \"--${key}\""
                    exit_code=${ERROR}
                    shift
                fi

            ;;

            *)
                # We bail immediately on unknown or malformed inputs
                echo "${STDOUT_OFFSET}ERROR:  Unknown command line argument ... exiting"
                exit
            ;;

        esac

    done

    # Get data from supplied urlbase
    if [ "${urlbase}" != "" ]; then
        action_type=`echo "${urlbase}" | ${my_awk} -F'/' '{print $4 "/" $5}'`

        case ${action_type} in

            rest/api)
                action="push"
                pageid=`echo "${urlbase}" | ${my_awk} -F'/' '{print $(NF-2)}'`
            ;;

            download/attachments)
                action="pull"
                filename=`echo "${urlbase}" | ${my_awk} -F'/' '{print $(NF-1)}' | ${my_awk} -F'?' '{print $1}'`
                pageid=`echo "${urlbase}" | ${my_awk} -F'/' '{print $NF}'`
            ;;

        esac

    fi

    if [ "${action}" = "" -o "${filename}" = "" -o "${pageid}" = "" -o "${username}" = "" ]; then
        err_msg="Not enough command line arguments detected"
        exit_code=${ERROR}
    fi


fi

# WHAT: Request a password
# WHY:  Needed later
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    while [ "${password}" = "" ]; do
        ${my_stty} -echo
        read -p "    Please enter the password for username: \"${username}\": " password
        password=`echo "${password}" | ${my_sed} -e 's?\`??g'`
        ${my_stty} echo

        if [ "${password}" = "" ]; then
            echo
            echo "    ERROR:  Password cannot be blank"
            echo
        fi

    done

fi

# WHAT: Construct a curl command
# WHY:  Needed later
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    remote_filename=`${my_basename} "${filename}"`

    # See if we have been passed a ${filename}.v${version}
    let contains_version=`echo "${filename}" | ${my_egrep} -c "\.v[0-9]+$"`

    if [ ${contains_version} -gt 0 ]; then
        file_version=`echo "${filename}" | ${my_awk} -F'.' '/.v[0-9]+$/ {print $NF}' | ${my_sed} -e 's/v/version=/g'`
        real_filename=`echo "${filename}" | ${my_sed} -e 's/\.v[0-9]*$//g'`
        remote_filename=`${my_basename} "${real_filename}"`
    fi

    ## Examples
    ## Push a file into confluence as a page attachment
    #curl -D- -u <username>:<password> -X POST -H "X-Atlassian-Token: nocheck" -F "file=@<file name>" https://<confluence hostname>/rest/api/content/<pageid>/child/attachment
    ##
    ## Pull a page attachment from confluence
    #curl -X GET -u <username>:<password> https://<confluence hostname>/download/attachments/<pageid>/<file name>?api=v2 > "<file name>"
    ## Pull a specific attachment version from confluence
    #curl -X GET -u <username>:<password> https://<confluence hostname>/download/attachments/<pageid>/<file name>?version=7 > "<file name>"

    case ${action} in 

        pull)

            if [ "${urlbase}" = "" ]; then
                urlbase_params="api=v2"

                if [ "${file_version}" != "" ]; then 
                    urlbase_params="${file_version}?${urlbase_params}"
                    #urlbase_params="${urlbase_params}?${file_version}"
                fi
     
                urlbase="${CONFLUENCE_URL}/download/attachments/${pageid}/${remote_filename}?${urlbase_params}"
            fi

            if [ "${debug}" = "" ]; then

                if [ -e "${filename}" ]; then
                    answer=""
                    echo

                    while [ "${answer}" = "" ] ;do
                        echo
                        read -p "    WARNING:  Filename \"${filename}\" exists ... overwrite? " answer
                        answer=`echo "${answer}" | ${my_sed} -e 's?\`??g'`

                        case ${answer} in

                            [Nn][Oo]|[Nn])
                                echo
                                echo "Operation cancelled by user"
                                exit ${SUCCESS}
                            ;;

                            [Yy]es|[Yy])
                                echo
                                echo "    * * * Local file \"${filename}\" WILL BE REMOVED * * *"
                                echo
                                read -p "    Press <ENTER> to continue or <CTRL>-C to quit ... " input
                                ${my_rm} -f "${filename}" 
                            ;;

                        esac
                            
                    done

                fi

            fi

            curl_command="${my_curl} -u ${username}:${password} -X GET ${urlbase} > ${filename} 2> /dev/null"
        ;;

        push)

            if [ -e "${filename}" ]; then
                minoredit=""

                if [ "${urlbase}" = "" ]; then
                    urlbase="${CONFLUENCE_URL}/rest/api/content/${pageid}/child/attachment"
                fi

                # See if file exists already
                already_exists=`${my_curl} -D- -u ${username}:${password} -X GET -H "X-Atlassian-Token: nocheck" ${urlbase} 2> /dev/null | ${my_egrep} "^{\"results\":" | ${my_jq} ".results[] | {title: .title, id: .id}" 2> /dev/null | ${my_egrep} -A1 "\"title\": \"${filename}\",$"`

                if [ "${already_exists}" != "" ]; then
                    attachmentid=`echo "${already_exists}" | ${my_egrep} "\"id\":" | ${my_awk} '{print $NF}' | ${my_sed} -e 's?"??g'`

                    # Change ${urlbase} to point to the data resource, which will
                    # create a new version of the same name
                    if [ "${attachmentid}" != "" ]; then
                        minoredit="-F\"minorEdit=false\""
                        urlbase="${CONFLUENCE_URL}/rest/api/content/${pageid}/child/attachment/${attachmentid}/data"
                    fi

                fi

                right_now=`${my_date}`
                curl_command="${my_curl} -D- -u ${username}:${password} -X POST -H \"X-Atlassian-Token: nocheck\" -F \"file=@${filename}\" -F \"comment=uploaded ${right_now}\" ${minoredit} ${urlbase} 2> /dev/null"
            else
                err_msg="Could not find file \"${filename}\""
                exit_code=${ERROR}
            fi

        ;;

        *)
            err_msg="Unknown action: \"${action}\""
            exit_code=${ERROR}
        ;;

    esac

fi

# WHAT: Do as asked
# WHY:  The reason we are here
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ "${curl_command}" != "" ]; then

        if [ "${debug}" != "" ]; then
            echo "My action is: ${action}"
            echo "My filename is: ${filename}"
            echo "My pageid is: ${pageid}"
            echo "My urlbase is: ${urlbase}"
            echo "My username is: ${username}"
            echo "My password is: ${password}"
            echo "My curl command is: ${curl_command}"
        else

            case ${action} in

                pull)
                    direction="from"
                    ${my_stty} -echo
                    eval "${curl_command}" 2> /dev/null
                    ${my_stty} echo

                    if [ -e "${filename}" ]; then
                        # Try to detect a page not found error
                        # Confluence will produce a page for 404 errors, which curl will then download,
                        # creating a false positive situation
                        let page_not_found=`egrep -ci "page not found|page does not exist" "${filename}"`
                        let authentication_failed=`egrep -ci "basic authentication failure" "${filename}"`

                        if [ ${page_not_found} -eq 0 -a ${authentication_failed} -eq 0 ]; then
                            let return_val=1
                        else
                            rm "${filename}"

                            if [ ${authentication_failed} -gt 0 ]; then
                                echo -ne "\n    Could not authenticate against Confluence URL ${urlbase} ... exiting\n"
                                exit 1
                            else
                                echo -ne "\n    There is no valid attachment link at URL: ${urlbase}\n" 
                                let return_val=0
                            fi

                        fi

                    else
                        let return_val=0
                    fi

                ;;

                push)

                    if [ ! -d "${temp_dir}" ]; then
                        ${my_mkdir} -p "${temp_dir}"
                    fi

                    direction="to"
                    ${my_stty} -echo
                    eval "${curl_command}" | ${my_egrep} "^\{\"" > "${temp_dir}/${temp_file}" 2> /dev/null
                    ${my_stty} echo

                    jq_query=".results[0]._links.webui"

                    if [ "${attachmentid}" != "" ]; then
                        jq_query="._links.webui"
                        #return_val=`${my_jq} "._links.webui" "${temp_dir}/${temp_file}" 2> /dev/null | ${my_egrep} -c "${remote_filename}"`
                    fi

                    jq_command="${my_jq} \"${jq_query}\" \"${temp_dir}/${temp_file}\" 2> /dev/null | ${my_egrep} -c \"${remote_filename}\""
                    return_val=`eval "${jq_command}"`

                    if [ -d "${temp_dir}" ]; then
                        ${my_rm} -rf "${temp_dir}"
                    fi

                ;;

            esac

            if [ ${return_val} -gt 0 ]; then
                echo -ne "\nSuccessfully ${action}ed file \"${filename}\" ${direction} ${urlbase}\n"
            else
                err_msg="Failed to ${action} file \"${filename}\" ${direction} ${urlbase}"
                exit_code=${ERROR}
            fi

        fi

    else
        err_msg="Failed to construct curl command for ${action} operation"
        exit_code=${ERROR}
    fi

fi

# WHAT: Complain if necessary and exit
# WHY:  Success or failure, either way we are through
#
if [ ${exit_code} -ne ${SUCCESS} ]; then

    if [ "${err_msg}" != "" ]; then
        echo -ne "\n\n"
        echo -ne "${STDOUT_OFFSET}ERROR:  ${err_msg} ... processing halted\n"
        echo
    fi

    echo
    echo -ne "${STDOUT_OFFSET}USAGE:  ${USAGE}\n"
    echo
fi

exit ${exit_code}
