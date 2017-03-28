#!/bin/sh

# THIS FILE IS PART OF THE CYLC SUITE ENGINE.
# Copyright (C) 2008-2017 NIWA
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

###############################################################################
# Bash/ksh93 functions for a cylc task job.
###############################################################################

###############################################################################
# The main function for a cylc task job.
cylc__job__main() {
    # Turn on xtrace in debug mode
    if "${CYLC_DEBUG:-false}"; then
        if [[ -n "${BASH:-}" ]]; then
            PS4='+[\D{%Y%m%dT%H%M%S%z}]\u@\h '
        fi
        set -x
    fi
    # Prelude
    typeset file_name=
    for file_name in \
        "${HOME}/.cylc/job-init-env.sh" \
        "${CYLC_DIR}/conf/job-init-env.sh" \
        "${CYLC_DIR}/conf/job-init-env-default.sh"
    do
        if [[ -f "${file_name}" ]]; then
            . "${file_name}" 1>'/dev/null' 2>&1
            break
        fi
    done
    # Init-Script
    cylc__job__run_inst_func 'global_init_script'
    cylc__job__run_inst_func 'init_script'
    # Start error and vacation traps
    typeset signal_name=
    for signal_name in ${CYLC_FAIL_SIGNALS}; do
        trap "cylc__job__trap_err ${signal_name}" "${signal_name}"
    done
    for signal_name in ${CYLC_VACATION_SIGNALS:-}; do
        trap "cylc__job__trap_vacation ${signal_name}" "${signal_name}"
    done
    set -euo pipefail
    # Export CYLC_ suite and task environment variables
    cylc__job__inst__cylc_env
    # Write task job self-identify
    USER="${USER:-$(whoami)}"
    typeset host="${HOSTNAME:-}"
    if [[ -z "${host}" ]]; then
        if [[ "$(uname)" == 'AIX' ]]; then
            # On AIX the hostname command has no '-f' option
            typeset host="$(hostname).$(namerslv -sn 2>'/dev/null' | awk '{print $2}')"
        else
            typeset host="$(hostname -f)"
        fi
    fi
    cat <<__OUT__
Suite    : ${CYLC_SUITE_NAME}
Task Job : ${CYLC_TASK_JOB} (try ${CYLC_TASK_TRY_NUMBER})
User@Host: ${USER}@${host}

__OUT__
    # Derived environment variables
    export CYLC_SUITE_LOG_DIR="${CYLC_SUITE_RUN_DIR}/log/suite"
    CYLC_SUITE_WORK_DIR_ROOT="${CYLC_SUITE_WORK_DIR_ROOT:-${CYLC_SUITE_RUN_DIR}}"
    export CYLC_SUITE_SHARE_DIR="${CYLC_SUITE_WORK_DIR_ROOT}/share"
    export CYLC_SUITE_WORK_DIR="${CYLC_SUITE_WORK_DIR_ROOT}/work"
    export CYLC_TASK_CYCLE_POINT="$(cut -d '/' -f 1 <<<"${CYLC_TASK_JOB}")"
    export CYLC_TASK_NAME="$(cut -d '/' -f 2 <<<"${CYLC_TASK_JOB}")"
    # The "10#" part ensures that the submit number is interpreted in base 10.
    # Otherwise, a zero padded number will be interpreted as an octal.
    export CYLC_TASK_SUBMIT_NUMBER=$((10#$(cut -d '/' -f 3 <<<"${CYLC_TASK_JOB}")))
    export CYLC_TASK_ID="${CYLC_TASK_NAME}.${CYLC_TASK_CYCLE_POINT}"
    export CYLC_TASK_LOG_ROOT="${CYLC_SUITE_RUN_DIR}/log/job/${CYLC_TASK_JOB}/job"
    if [[ -n "${CYLC_TASK_WORK_DIR_BASE:-}" ]]; then
        # Note: value of CYLC_TASK_WORK_DIR_BASE may contain variable
        # substitution syntax including some of the derived variables above, so
        # it can only be derived at point of use.
        CYLC_TASK_WORK_DIR_BASE="$(eval echo "${CYLC_TASK_WORK_DIR_BASE}")"
    else
        CYLC_TASK_WORK_DIR_BASE="${CYLC_TASK_CYCLE_POINT}/${CYLC_TASK_NAME}"
    fi
    export CYLC_TASK_WORK_DIR="${CYLC_SUITE_WORK_DIR}/${CYLC_TASK_WORK_DIR_BASE}"
    typeset contact="${CYLC_SUITE_RUN_DIR}/.service/contact"
    if [[ -f "${contact}" ]]; then
        export CYLC_SUITE_HOST="$(sed -n 's/^CYLC_SUITE_HOST=//p' "${contact}")"
        export CYLC_SUITE_OWNER="$(sed -n 's/^CYLC_SUITE_OWNER=//p' "${contact}")"
    fi
    # DEPRECATED environment variables
    export CYLC_SUITE_SHARE_PATH="${CYLC_SUITE_SHARE_DIR}"
    export CYLC_SUITE_INITIAL_CYCLE_TIME="${CYLC_SUITE_INITIAL_CYCLE_POINT}"
    export CYLC_SUITE_FINAL_CYCLE_TIME="${CYLC_SUITE_FINAL_CYCLE_POINT}"
    export CYLC_TASK_CYCLE_TIME="${CYLC_TASK_CYCLE_POINT}"
    export CYLC_TASK_WORK_PATH="${CYLC_TASK_WORK_DIR}"
    # Env-Script
    cylc__job__run_inst_func 'env_script'
    # Send task started message
    cylc task message 'started' &
    CYLC_TASK_MESSAGE_STARTED_PID=$!
    # Access to the suite bin directory
    if [[ -n "${CYLC_SUITE_DEF_PATH:-}" && -d "${CYLC_SUITE_DEF_PATH}/bin" ]]
    then
        export PATH="${CYLC_SUITE_DEF_PATH}/bin:${PATH}"
    fi
    # Create share and work directories
    mkdir -p "${CYLC_SUITE_SHARE_DIR}" || true
    mkdir -p "$(dirname "${CYLC_TASK_WORK_DIR}")" || true
    mkdir -p "${CYLC_TASK_WORK_DIR}"
    cd "${CYLC_TASK_WORK_DIR}"
    # User Environment, Pre-Script, Script and Post-Script
    typeset func_name=
    for func_name in 'user_env' 'pre_script' 'script' 'post_script'; do
        cylc__job__run_inst_func "${func_name}"
    done
    # Empty work directory remove
    cd
    rmdir "${CYLC_TASK_WORK_DIR}" 2>'/dev/null' || true
    # Send task succeeded message
    wait "${CYLC_TASK_MESSAGE_STARTED_PID}" 2>'/dev/null' || true
    cylc task message 'succeeded' || true
    trap '' EXIT
    exit 0
}

###############################################################################
# Run a function in the task job instance file, if possible.
# Arguments:
#   func_name - name of function without the "cylc__job__inst__" prefix
# Returns:
#   return 0, or the return code of the function if called
cylc__job__run_inst_func() {
    typeset func_name="$1"
    shift 1
    if typeset -f "cylc__job__inst__${func_name}" 1>'/dev/null' 2>&1; then
        "cylc__job__inst__${func_name}" "$@"
    fi
}

###############################################################################
# Trap error signals.
# Globals:
#   CYLC_FAIL_SIGNALS
#   CYLC_TASK_MESSAGE_STARTED_PID
#   CYLC_VACATION_SIGNALS
# Arguments:
#   trapped_signal - trapped signal
# Returns:
#   exit 1
cylc__job__trap_err() {
    typeset trapped_signal="$1"
    echo "Received signal ${trapped_signal}" >&2
    typeset signal_name=
    for signal_name in ${CYLC_VACATION_SIGNALS:-} ${CYLC_FAIL_SIGNALS}; do
        trap '' "${signal_name}"
    done
    if [[ -n "${CYLC_TASK_MESSAGE_STARTED_PID:-}" ]]; then
        wait "${CYLC_TASK_MESSAGE_STARTED_PID}" 2>'/dev/null' || true
    fi
    cylc task message -p 'CRITICAL' \
        "Task job script received signal ${trapped_signal}" 'failed' || true
    cylc__job__run_inst_func 'err_script' "${trapped_signal}" >&2
    exit 1
}

###############################################################################
# Trap preempt/vacation signals.
# Globals:
#   CYLC_FAIL_SIGNALS
#   CYLC_TASK_MESSAGE_STARTED_PID
#   CYLC_VACATION_SIGNALS
# Arguments:
#   trapped_signal - trapped signal
# Returns:
#   exit 1
cylc__job__trap_vacation() {
    typeset trapped_signal="$1"
    echo "Received signal ${trapped_signal}" >&2
    typeset signal_name=
    for signal_name in ${CYLC_VACATION_SIGNALS:-} ${CYLC_FAIL_SIGNALS}; do
        trap '' "${signal_name}"
    done
    if [[ -n "${CYLC_TASK_MESSAGE_STARTED_PID:-}" ]]; then
        wait "${CYLC_TASK_MESSAGE_STARTED_PID}" 2'>/dev/null' || true
    fi
    cylc task message -p 'WARNING' \
        "Task job script vacated by signal ${trapped_signal}" || true
    exit 1
}
