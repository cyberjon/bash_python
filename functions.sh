#!/bin/bash
#******************************************************************************

# Copyright 2015 Clark Hsu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#******************************************************************************
# How To

#******************************************************************************
# Source

LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#******************************************************************************

check_if_root_user()
{
    if [[ ${UID} -ne 0 ]]; then
        echo "[Warning] This script was designed for root user.  Please rerun the script as root user!"
        exit 1
    fi
}

#******************************************************************************

function export_locale()
{
    export LANGUAGE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_TYPE=en_US.UTF-8
}

#******************************************************************************

function log_s()
{
    echo ""
    echo "*******************************************************************************"
    echo ""
}

function log_m()
{
    log_s
    echo "[MSG] ${*}"
}

function log_i()
{
    echo "[INFO] ${*}"
}

function log_e()
{
    echo "[ERR] ${*}"
}

function log_a()
{
    echo "[CMD] $@"
    "$@"
}

#******************************************************************************

function detect_group_user()
{
    log_m "Detect Group and User"

    USER_NAME=`id -n -u`
    ADMIN_NAME=$(grep '^admin:' /etc/group >&/dev/null && echo admin || echo adm)
    GROUP_NAME=`id -n -g`
    USER_ID=`id -u`
    GROUP_ID=`id -g`

    log_i "USER_NAME=${USER_NAME}"
    log_i "ADMIN_NAME=${ADMIN_NAME}"
    log_i "GROUP_NAME=${GROUP_NAME}"
    log_i "USER_ID=${USER_ID}"
    log_i "GROUP_ID=${GROUP_ID}"

    log_s
}

function detect_env()
{
    log_m "Detect Environment"

    if [ -e "/usr/bin/lsb_release" ]; then
        lsb_release -a
    fi

    if [ -e "/usr/bin/sw_vers" ]; then
        sw_vers
    fi

    HOST_EXE=""
    HOST_OS=`uname -s`
    case "${HOST_OS}" in
        Darwin)
            HOST_OS=darwin
            ;;
        Linux)
            # note that building  32-bit binaries on x86_64 is handled later
            HOST_OS=linux
            ;;
        FreeBsd)  # note: this is not tested
            HOST_OS=freebsd
            ;;
        CYGWIN*|*_NT-*)
            HOST_OS=windows
            HOST_EXE=.exe
            if [ "x${OSTYPE}" = xcygwin ] ; then
                HOST_OS=cygwin
            fi
            ;;
    esac
    log_i "HOST_OS=${HOST_OS}"
    log_i "HOST_EXE=${HOST_EXE}"

    HOST_ARCH=`uname -m`
    case "${HOST_ARCH}" in
        i?86)
            HOST_ARCH=x86
            # "uname -m" reports i386 on Snow Leopard even though its architecture is
            # 64-bit. In order to use it to build 64-bit toolchains we need to fix the
            # reporting anomoly here.
            if [ "${HOST_OS}" = darwin ] ; then
                if ! echo __LP64__ | (CCOPTS= gcc -E - 2>/dev/null) | grep -q __LP64__ ; then
                # or if gcc -dM -E - < /dev/null | grep -q __LP64__; then
                    HOST_ARCH=x86_64
                fi
            fi
            ;;
        amd64)
            HOST_ARCH=x86_64
            ;;
        powerpc)
            HOST_ARCH=ppc
            ;;
    esac
    HOST_FILE_PROGRAM="file"
    case "${HOST_OS}-${HOST_ARCH}" in
        linux-x86_64|darwin-x86_64)
            if [ "${HOST_OS}" = "darwin" ]; then
                SYSTEM_FILE_PROGRAM="/usr/bin/file"
                test -x "${SYSTEM_FILE_PROGRAM}" && HOST_FILE_PROGRAM="${SYSTEM_FILE_PROGRAM}"
            fi
            "${HOST_FILE_PROGRAM}" -L "${SHELL}" | grep -q "x86[_-]64"
            if [ $? != 0 ]; then
                  # $SHELL is not a 64-bit executable, so assume our userland is too.
                  log_i "Detected 32-bit userland on 64-bit kernel system!"
                  HOST_ARCH=x86
            fi
            ;;
    esac
    log_i "HOST_ARCH=${HOST_ARCH}"

    HOST_TAG=${HOST_OS}-${HOST_ARCH}
    # Special case for windows-x86 => windows
    case ${HOST_TAG} in
        windows-x86|cygwin-x86)
            HOST_TAG="windows"
            ;;
    esac
    log_i "HOST_TAG=${HOST_TAG}"

    HOST_CPU=`uname -p`
    case "${HOST_OS}" in
        linux)
            HOST_NUM_CPUS=`cat /proc/cpuinfo | grep processor | wc -l`
            ;;
        darwin|freebsd)
            HOST_NUM_CPUS=`sysctl -n hw.ncpu`
            ;;
        windows|cygwin)
            HOST_NUM_CPUS=${NUMBER_OF_PROCESSORS}
            ;;
        *)  # let's play safe here
            HOST_NUM_CPUS=1
    esac
    log_i "HOST_NUM_CPUS=${HOST_NUM_CPUS}"

    case "${HOST_OS}" in
        linux)
            HOST_RAM=$(free -m | grep "Mem:" |awk '{print $2}')
            ;;
        darwin|freebsd)
            HOST_RAM=$(sysctl -a | grep hw.memsize | awk '{print $3}')
            ;;
        *)  # let's play safe here
            HOST_RAM=""
    esac
    log_i "HOST_RAM=${HOST_RAM}"

    HOST_HHD=$(df -h | sed -n 2p | awk '{print $2}')
    log_i "HOST_HHD=${HOST_HHD}"

    log_s
}

function detect_owner_group_permission()
{
    if [ $# != "1" ]; then
        log_e "Usage: ${FUNCNAME} <dir/file>"
        exit 1
    else
        detect_env
        if [ -f "${1}" ]; then
            DF_TYPE="file"

            case "${HOST_OS}" in
                linux)
                    F_USER=$(stat -c "%U" "${1}")
                    F_GROUP=$(stat -c "%G" "${1}")
                    F_PERM=$(stat -c "%a" "${1}")
                    ;;
                darwin|freebsd)
                    F_USER=$(stat -f "%Su" "${1}")
                    F_GROUP=$(stat -f "%Sg" "${1}")
                    F_PERM=$(stat -f "%Lp" "${1}")
                    ;;
            esac
            D_PATH=$(dirname "${1}")
            F_NAME=$(basename "${1}")
        elif [ -d "${1}" ]; then
            DF_TYPE="directory"
            D_PATH="${1}"
        else
            DF_TYPE="directory"
            D_PATH=$(dirname "${1}")
            if [ ! -e "${D_PATH}" ]; then
                mkdir -p "${D_PATH}"
            fi
        fi

        case "${HOST_OS}" in
            linux)
                D_USER=$(stat -c "%U" "${D_PATH}")
                D_GROUP=$(stat -c "%G" "${D_PATH}")
                D_PERM=$(stat -c "%a" "${D_PATH}")
                ;;
            darwin|freebsd)
                D_USER=$(stat -f "%Su" "${D_PATH}")
                D_GROUP=$(stat -f "%Sg" "${D_PATH}")
                D_PERM=$(stat -f "%Lp" "${D_PATH}")
                ;;
        esac

        if [ "${F_USER}" == "" ]; then
            F_USER="${D_USER}"
            F_GROUP="${D_GROUP}"
            F_PERM="${D_PERM}"
        fi

        log_i "DF_TYPE=${DF_TYPE}"
        log_i "F_NAME=${F_NAME}"
        log_i "D_PATH=${D_PATH}"
        log_i "F_USER=${F_USER}"
        log_i "F_GROUP=${F_GROUP}"
        log_i "F_PERM=${F_PERM}"
        log_i "D_USER=${D_USER}"
        log_i "D_GROUP=${D_GROUP}"
        log_i "D_PERM=${D_PERM}"
    fi
}

function clean_owner_group_permission()
{
    DF_TYPE=''
    F_NAME=''
    D_PATH=''
    F_USER=''
    F_GROUP=''
    F_PERM=''
    D_USER=''
    D_GROUP=''
    D_PERM=''
}

#******************************************************************************

function match_pattern()
{
    if [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <pattern> <input string>"
        exit 1
    else
        echo "${2}" | grep -q -E -e "${1}"
    fi
}

function find_program()
{
    if [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <variable_name> <program name>"
        exit 1
    else
        local PROG RET
        PROG=`which ${2} 2>/dev/null || :`
        RET=$?
        if [ $RET != 0 ]; then
            PROG=
        fi
        eval ${1}=\"${PROG}\"
        return $RET
    fi
}

#******************************************************************************

# Download a file with either 'curl', 'wget' or 'scp'
#
# ${1}: source URL (e.g. http://foo.com, ssh://blah, /some/path)
# ${2}: target file (/path/filename)
function copy_files()
{
    if [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <src_location> <dest_location>"
        exit 1
    else
        find_program CMD_CURL curl
        find_program CMD_WGET wget
        find_program CMD_SCP scp

        log_i "Copy files from ${1} to ${2}"

        # Is this HTTP, HTTPS or FTP ?
        # curl <src_location> -o <dest_location>
        if match_pattern "^(http|https|ftp):.*" "${1}"; then

            detect_owner_group_permission "${2}"
            local C_TYPE="${DF_TYPE}"
            if [ "${C_TYPE}" == "file" ]; then
                sudo -u "${F_USER}" rm "${2}"
            fi
            sudo chmod 777 "${D_PATH}"
            local O_USER="${D_USER}"
            clean_owner_group_permission

            if [ -n "${CMD_CURL}" ] ; then
                log_a time sudo -u "${O_USER}" "${CMD_CURL}" -L "${1}" -o "${2}"
            elif [ -n "${CMD_WGET}" ] ; then
                log_a time sudo -u "${O_USER}" "${CMD_WGET}" "${1}" -O "${2}"
            else
                echo "Please install wget or curl on this machine"
                exit 1
            fi

            return
        fi

        # Is this SSH ?
        # Accept both ssh://<path> or <machine>:<path>
        # scp -r <user_name>@<ip>:<src_location> <dest_location>
        if match_pattern "^(ssh|[^:]+):.*" "${1}"; then
            if [ -n "${CMD_SCP}" ] ; then
                SCP_SRC=`echo ${1} | sed -e s%ssh://%%g`
                if [ "${PASSWORD}" != "" ]; then
                    time sshpass -p "${PASSWORD}" "${CMD_SCP}" -rp "${SCP_SRC}" "${2}"
                elif [ -e "${TOP_DIR}/pem/${MACHINE_TYPE}/${OS_TYPE}/${REMOTE_TYPE}/${NODE_TYPE}/${NODE}/PEM/${PEM}" ]; then
                    time "${CMD_SCP}" -i "${TOP_DIR}/pem/${MACHINE_TYPE}/${OS_TYPE}/${REMOTE_TYPE}/${NODE_TYPE}/${NODE}/PEM/${PEM}" -rp "${SCP_SRC}" "${2}"
                else
                    time "${CMD_SCP}" -rp "${SCP_SRC}" "${2}"
                fi
            else
                echo "Please install scp on this machine"
                exit 1
            fi
            return
        fi

        # Is this SSH ?
        # Accept both ssh://<path> or <machine>:<path>
        # scp -r <src_location> <user_name>@<ip>:<dest_location>
        if match_pattern "^(ssh|[^:]+):.*" "${2}"; then
            if [ -n "${CMD_SCP}" ] ; then
                SCP_DEST=`echo ${2} | sed -e s%ssh://%%g`
                if [ "${PASSWORD}" != "" ]; then
                    time sshpass -p "${PASSWORD}" "${CMD_SCP}" -rp "${1}" "${SCP_DEST}"
                elif [ -e "${TOP_DIR}/pem/${MACHINE_TYPE}/${OS_TYPE}/${REMOTE_TYPE}/${NODE_TYPE}/${NODE}/PEM/${PEM}" ]; then
                    time "${CMD_SCP}" -i "${TOP_DIR}/pem/${MACHINE_TYPE}/${OS_TYPE}/${REMOTE_TYPE}/${NODE_TYPE}/${NODE}/PEM/${PEM}" -rp "${1}" "${SCP_DEST}"
                else
                    time "${CMD_SCP}" -rp "${1}" "${SCP_DEST}"
                fi
            else
                echo "Please install scp on this machine"
                exit 1
            fi
            return
        fi

        # Is this a file copy ?
        # Accept both file://<path> or /<path>
        # cp -R <src_location>/<file> <dest_location>
        if match_pattern "^(file://|/).*" "${1}"; then
            CP_SRC=`echo ${1} | sed -e s%^file://%%g`

            detect_owner_group_permission "${CP_SRC}"
            log_i "TYPE: ${DF_TYPE}"
            if [ "${DF_TYPE}" == "file" ]; then
                local I_PERM="${F_PERM}"
                local I_USER="${F_USER}"
            else
                local I_PERM="${D_PERM}"
                local I_USER="${D_USER}"
            fi
            clean_owner_group_permission

            detect_owner_group_permission "${2}"
            log_i "TYPE: ${DF_TYPE}"
            if [ "${DF_TYPE}" == "file" ]; then
                local O_PERM="${F_PERM}"
                local O_USER="${F_USER}"
            else
                local O_PERM="${D_PERM}"
                local O_USER="${D_USER}"
            fi
            clean_owner_group_permission

            log_i "Permission: ${I_PERM}"
            case ${I_PERM} in
                "700" | "600" | "755" | "655" | "644" | "544")
                    if [ "${I_USER}" == "root" ] || [ "${O_USER}" == "root" ]; then
                        time sudo cp -R "${CP_SRC}" "${2}"
                    else
                        time sudo -u "${I_USER}" cp -R "${CP_SRC}" "${2}"
                    fi
                    ;;
                *)
                    time cp -R "${CP_SRC}" "${2}"
                    ;;
            esac
            return
        fi
    fi
}

#******************************************************************************

# Unpack a given archive
#
# ${1}: <path>/<filename>.zip
# ${2}: [<output_path>]
function uncompress()
{
    if [ $# != "1" ] && [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <path>/<filename>.zip [<output_path>]"
        exit 1
    else
        local ARCHIVE="${1}"
        local DIR=${2-.}
        local RESULT TARFLAGS ZIPFLAGS
        TARFLAGS="xpf"
        ZIPFLAGS="-o" #-q
        #mkdir -p "${DIR}"

        detect_owner_group_permission "${ARCHIVE}"
        local I_USER="${F_USER}"
        clean_owner_group_permission

        case "${ARCHIVE}" in
            *.zip)
                #install_zip_deb
                if [ "${HOST_OS}" == "linux" ] && [ ! -e "/usr/bin/unzip" ]; then
                    sudo -E apt-get install -y --force-yes zip unzip
                fi
                (cd "${DIR}" && log_a time sudo -u "${I_USER}" unzip ${ZIPFLAGS} "${ARCHIVE}")
                ;;
            *.tar)
                log_a time sudo -u "${I_USER}" tar ${TARFLAGS} "${ARCHIVE}" -C "${DIR}"
                ;;
            *.tar.gz|*.tgz)
                log_a time sudo -u "${I_USER}" tar z${TARFLAGS} "${ARCHIVE}" -C "${DIR}"
                ;;
            *.tar.bz2)
                log_a time sudo -u "${I_USER}" tar j${TARFLAGS} "${ARCHIVE}" -C "${DIR}"
                ;;
            *)
                log_e "Invalid compress file extension"
                ;;
        esac
        # remove ._* files by MacOSX to preserve resource forks we don't need
        find "${DIR}" -name "\._*" -exec rm {} \;
        sudo -u "${I_USER}" du -sh "${ARCHIVE%.*}".*
    fi
}

# Pack a given archive
#
# ${1}: <path>/<filename>.zip
# ${2}: <dirname/filename>
function compress()
{
    if [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <path>/<filename>.zip <dirname/filename>"
        exit 1
    else
        local ARCHIVE="${1}"
        local SRCDIR="${2}"
        local TARFLAGS ZIPFLAGS
        TARFLAGS="cf"
        ZIPFLAGS="-r" #-9qr
        # Ensure symlinks are stored as is in zip files. for toolchains
        # this can save up to 7 MB in the size of the final archive
        #ZIPFLAGS="${ZIPFLAGS} --symlinks"

        detect_owner_group_permission "${SRCDIR}"
        local I_USER="${D_USER}"
        clean_owner_group_permission

        case "${ARCHIVE}" in
            *.zip)
                #install_zip_deb
                if [ ! -e "/usr/bin/zip" ] && [ "${HOST_OS}" == "linux" ]; then
                    sudo -E apt-get install -y --force-yes zip unzip
                fi
                log_a time sudo -u "${I_USER}" zip ${ZIPFLAGS} "${ARCHIVE}" "${SRCDIR}"
                ;;
            *.tar)
                log_a time sudo -u "${I_USER}" tar ${TARFLAGS} "${ARCHIVE}" "${SRCDIR}"
                ;;
            *.tar.gz|*.tgz)
                log_a time sudo -u "${I_USER}" tar z${TARFLAGS} "${ARCHIVE}" "${SRCDIR}"
                ;;
            *.tar.bz2)
                log_a time sudo -u "${I_USER}" tar j${TARFLAGS} "${ARCHIVE}" "${SRCDIR}"
                ;;
            *)
                log_e "Invalid compress file extension"
                ;;
        esac
        sudo -u "${I_USER}" du -sh "${ARCHIVE%.*}".*
    fi
}

#******************************************************************************

function set_configuration_file() 
{
    local INDEX=1
    local PARAMETERS=()
    for ELEMENT in "$@"
    do
        IFS=':', read -ra ARRAY <<< "${ELEMENT}"
        if [[ "${ARRAY[0]}" = "infile" ]]; then
            local INPUT=${ARRAY[1]}
            continue
        elif [[ "${ARRAY[0]}" = "outfile" ]]; then
            local OUTPUT=${ARRAY[1]}
            continue
        fi
        PARAMETERS[${INDEX}]="-e s#${ARRAY[0]}#${ARRAY[1]}#g "
        PARAMETERS+=${PARAMETERS[${INDEX}]}
        i=$((${INDEX} + 1))
    done

    if [[ "${OUTPUT}" ]]; then
        if [ -e "${OUTPUT}" ]; then
            cp ${OUTPUT} ${OUTPUT}.org
        fi
        sed ${PARAMETERS} ${INPUT} > ${OUTPUT}
    else
        cp ${INPUT} ${INPUT}.org
        sed -i ${PARAMETERS} ${INPUT}
    fi
}

#******************************************************************************

function read_and_confirm()
{
    local REASON=""
    if [ $# == "3" ]; then
        REASON="${3}"
    elif [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <message> <variable> [<value>]"
        exit 1
    fi

    while [ "${REASON}" == "" ]
    do
        echo ""
        #echo "Please enter REASON: "
        echo "Please enter ${1}: "
        read REASON

        local INPUT=0
        while [ ${INPUT} -le 0 -o ${INPUT} -ge 3 ]
        do
            echo ""
            echo "Please confirm: " ${REASON}
            echo " 1) Yes"
            echo " 2) No"
            echo ""
            echo "Please enter your choice:"
            read INPUT
            #echo "Your INPUT is ${INPUT}"
            case ${INPUT} in
                1)
                    ;;
                2)
                    REASON=""
                    ;;
                *)
                    log_e "Invalid INPUT: ${INPUT}"
                    INPUT=0
                    ;;
            esac
        done
    done
    eval ${2}=\"${REASON}\"
}

function read_multiple_line()
{
    local  __resultvar=${1}
    local  RESULT=""
    while read -r LINE
    do
        if [ "${LINE}" = "" ]
        then
            break
        fi
        #RESULT="${RESULT}\n\t${LINE}"
        RESULT="${RESULT}\n${LINE}"
    done

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${RESULT}'"
    else
        echo "${RESULT}"
    fi
}

function read_multiple_line_and_confirm()
{
    local REASON=""
    if [ $# == "3" ]; then
        REASON="${3}"
    elif [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <message> <variable> [<value>]"
        exit 1
    fi

    while [ "${REASON}" == "" ]
    do
        echo ""
        #echo "Please enter REASON: "
        echo "Please enter ${1}: "
        echo "******************************************************************************"
        read_multiple_line REASON

        local INPUT=0
        while [ ${INPUT} -le 0 -o ${INPUT} -ge 3 ]
        do
            echo ""
            echo "Please confirm: " ${REASON}
            echo " 1) Yes"
            echo " 2) No"
            echo ""
            echo "Please enter your choice:"
            read INPUT
            #echo "Your INPUT is ${INPUT}"
            case ${INPUT} in
                1)
                    ;;
                2)
                    REASON=""
                    ;;
                *)
                    log_e "Invalid INPUT: ${INPUT}"
                    INPUT=0
                    ;;
            esac
        done
    done
    eval ${2}=\"${REASON}\"
}

function enter_file_name()
{
    local REASON=""
    if [ $# == "4" ]; then
        REASON="${4}"
    elif [ $# != "3" ]; then
        log_e "Usage: ${FUNCNAME} <path> <message> <variable> [<value>]"
        exit 1
    fi

    while [ "${REASON}" == "" ]
    do
        echo "List existing file in ${1}..."
        ls "${1}"

        echo ""
        #echo "Please enter REASON: "
        echo "Please enter ${2}: "
        read REASON

        local INPUT=0
        while [ ${INPUT} -le 0 -o ${INPUT} -ge 3 ]
        do
            echo ""
            echo "Please confirm: " ${REASON}
            echo " 1) Yes"
            echo " 2) No"
            echo ""
            echo "Please enter your choice:"
            read INPUT
            #echo "Your INPUT is ${INPUT}"
            case ${INPUT} in
                1)
                    ;;
                2)
                    REASON=""
                    ;;
                *)
                    log_e "Invalid INPUT: ${INPUT}"
                    INPUT=0
                    ;;
            esac
        done
    done
    eval ${3}=\"${REASON}\"
}

function confirm_yn()
{
    local OPT=""
    if [ $# == "3" ]; then
        OPT="${3}"
    elif [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <message> <variable> [<value>]"
    fi

    local INPUT=0
    local SIZE=3
    while [ ${INPUT} -le 0 -o ${INPUT} -ge ${SIZE} ]
    do
        if [ "${OPT}" == "" ] || [ ${OPT} -le 0 -o ${OPT} -ge ${SIZE} ]; then
            echo ""
            echo "${1}:"
            echo " 1) Yes"
            echo " 2) No"
            echo ""
            echo "Please enter your choice:"
            read INPUT
            #echo "Your INPUT is ${INPUT}"
        elif [ ${OPT} -gt 0 -o ${OPT} -lt ${SIZE} ]; then
            INPUT=$OPT
        fi

        case ${INPUT} in
            1)
                ENABLE="yes"
                ;;
            2)
                ENABLE="no"
                ;;
            *)
                log_e "Invalid INPUT: ${INPUT}"
                INPUT=0
                ;;
        esac
    done
    eval ${2}=\"${ENABLE}\"
}

function confirm_tf()
{
    local OPT=""
    if [ $# == "3" ]; then
        OPT="${3}"
    elif [ $# != "2" ]; then
        log_e "Usage: ${FUNCNAME} <message> <variable> [<value>]"
    fi

    local INPUT=0
    local SIZE=3
    while [ ${INPUT} -le 0 -o ${INPUT} -ge ${SIZE} ]
    do
        if [ "${OPT}" == "" ] || [ ${OPT} -le 0 -o ${OPT} -ge ${SIZE} ]; then
            echo ""
            echo "${1}:"
            echo " 1) True"
            echo " 2) False"
            echo ""
            echo "Please enter your choice:"
            read INPUT
            #echo "Your INPUT is ${INPUT}"
        elif [ ${OPT} -gt 0 -o ${OPT} -lt ${SIZE} ]; then
            INPUT=$OPT
        fi

        case ${INPUT} in
            1)
                ENABLE="true"
                ;;
            2)
                ENABLE="false"
                ;;
            *)
                log_e "Invalid INPUT: ${INPUT}"
                INPUT=0
                ;;
        esac
    done
    eval ${2}=\"${ENABLE}\"
}

function select_x_from_path()
{
    if [ $# == "4" ]; then
        TYPE="${4}"
    elif [ $# != "3" ]; then
        log_e "Usage: ${FUNCNAME} <path> <message> <variable> [<value>]"
        exit 1
    fi

    if [ "${4}" == "" ]; then
        local ROOT_FOLDER="${1}"
        if [ ! -e "${ROOT_FOLDER}" ]; then
            log_e "${ROOT_FOLDER} Cannot be found"
            exit 1
        fi
        cd ${ROOT_FOLDER}

        local OPTIONS=(*)
        echo
        echo "Enter the Number of ${2} to Be Select: "
        local PS3="Please enter your choice: "
        select OPTION in "${OPTIONS[@]}"
        do
            echo "${REPLY} ${OPTIONS[ ${REPLY} - 1 ]}"
            TYPE="${OPTIONS[ ${REPLY} - 1 ]}"
            break;
        done

    fi
    eval ${3}=\"${TYPE}\"
}

function select_x_from_array()
{
    if [ $# == "4" ]; then
        TYPE="${4}"
    elif [ $# != "3" ]; then
        log_e "Usage: ${FUNCNAME} <array> <message> <variable> [<value>]"
        exit 1
    fi

    if [ "${4}" == "" ]; then
        local OPTIONS=(${1})
        echo
        echo "Enter the Number of ${2} to Be Select: "
        local PS3="Please enter your choice: "
        select OPTION in "${OPTIONS[@]}"
        do
            echo "${REPLY} ${OPTIONS[ ${REPLY} - 1 ]}"
            TYPE="${OPTIONS[ ${REPLY} - 1 ]}"
            break;
        done

    fi
    eval ${3}=\"${TYPE}\"
}

#******************************************************************************
