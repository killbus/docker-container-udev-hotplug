#!/bin/bash

. /usr/src/scripts/common.sh

export HOME=$(get_environment_value HOME)
export DOCKER_HOST=$(get_environment_value DOCKER_HOST)
export DOCKER_TLS_CERTDIR=$(get_environment_value DOCKER_TLS_CERTDIR)
export DOCKER_TLS_VERIFY=$(get_environment_value DOCKER_TLS_VERIFY)
export XDG_RUNTIME_DIR=$(get_environment_value XDG_RUNTIME_DIR)
export DOCKER_CERT_PATH=$(get_environment_value DOCKER_CERT_PATH)

# initial docker
_should_tls() {
    [ -n "${DOCKER_TLS_CERTDIR:-}" ] &&
        [ -s "$DOCKER_TLS_CERTDIR/client/ca.pem" ] &&
        [ -s "$DOCKER_TLS_CERTDIR/client/cert.pem" ] &&
        [ -s "$DOCKER_TLS_CERTDIR/client/key.pem" ]
}

# if we have no DOCKER_HOST but we do have the default Unix socket (standard or rootless), use it explicitly
if [ -z "${DOCKER_HOST:-}" ] && [ -S /var/run/docker.sock ]; then
    export DOCKER_HOST=unix:///var/run/docker.sock
elif [ -z "${DOCKER_HOST:-}" ] && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" && [ -S "$XDG_RUNTIME_DIR/docker.sock" ]; then
    export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
fi

# if DOCKER_HOST isn't set (no custom setting, no default socket), let's set it to a sane remote value
if [ -z "${DOCKER_HOST:-}" ]; then
    if _should_tls || [ -n "${DOCKER_TLS_VERIFY:-}" ]; then
        export DOCKER_HOST='tcp://docker:2376'
    else
        export DOCKER_HOST='tcp://docker:2375'
    fi
fi
if [ "${DOCKER_HOST#tcp:}" != "$DOCKER_HOST" ] &&
    [ -z "${DOCKER_TLS_VERIFY:-}" ] &&
    [ -z "${DOCKER_CERT_PATH:-}" ] &&
    _should_tls \
    ; then
    export DOCKER_TLS_VERIFY=1
    export DOCKER_CERT_PATH="$DOCKER_TLS_CERTDIR/client"
fi

check_docker_cmd() {
    local __ret=$1

    [ -x "$(command -v docker)" ]
    local _result=$?

    if (($_result == 1)); then

        unset __ret
    else
        eval $__ret=true
    fi
}

ere_quote() {
    sed 's/[][\.|$(){}?+*^]/\\&/g' <<<"$*"
}

in_array() {
    local -n arr=$1 #by name reference
    local key=$2
    if printf '%s\n' "${arr[@]}" | grep -q -P "^$(ere_quote ${key})$"; then
        return 0
    fi
    return 1
}

get_sc_by_dev() {
    sc_groups=$1
    devuuid=$2
    declare -a sc
    IFS=';' read -ra sc_groups <<<"$sc_groups"
    for sc_group in ${sc_groups[@]}; do
        IFS='|' read -ra sc_group <<<"$sc_group"
        IFS=',' read -ra devs <<<"${sc_group[0]}"
        IFS=',' read -ra sc <<<"${sc_group[1]}"
        if in_array devs $devuuid || in_array devs "+${devuuid}"; then
            all_rule_matched=true
            for dev in ${devs[@]}; do
                if [[ $dev == *"${devuuid}" ]]; then
                    continue
                fi
                # check whether required device is mounted or unmounted
                if [ "${dev:0:1}" = "+" ]; then
                    dev=${dev:1}
                    findmnt -rno SOURCE,TARGET -S PARTUUID=$dev >/dev/null
                    mounted=$?
                    if [ "$ACTION" = "add" ]; then
                        [ $mounted -eq 0 ] && continue
                        all_rule_matched=false
                        break
                    else
                        [ $mounted -ne 0 ] && continue
                        all_rule_matched=false
                        break
                    fi
                fi
            done
            if $all_rule_matched; then
                echo "${sc[@]}"
                break
            fi
        fi
    done
}

get_docker_sc() {
    _docker_available=
    check_docker_cmd _docker_available
    local type=$1
    local devuuid=$2
    declare -a event_action_sctype=($(echo $type | tr "_" " "))
    local sctype=${event_action_sctype[-1]}
    local action=${event_action_sctype[-2]}

    if [ "${_docker_available}" = true ]; then
        environment_key=$(printf '%s\n' "$type" | awk '{ print toupper($0) }')
        scs_devs_groups=$(get_environment_value "${environment_key}")
        if [ -z "${scs_devs_groups}" ]; then
            info "${environment_key} is empty. Won't attempt to ${action} ${sctype}."
        else
            info "Got value of ${environment_key}: ${scs_devs_groups}. Splitting values."
            declare -a scs=($(get_sc_by_dev ${scs_devs_groups[@]} $devuuid))
            if [[ -n $scs ]]; then
                info "Values split! Got '${scs[@]}'"
                echo "${scs[@]}"
            fi
        fi
    else
        info "Docker command is not available. Docker functionality will not work!"
    fi
}

action_containers() {
    local devuuid=$1
    local event=$( [ "${ACTION}" = "remove" ] && echo 'unmount' || echo 'mount' )
    declare -a containers
    declare -a actions=(restart start stop remove)

    for action in ${actions[@]}; do
        containers=($(get_docker_sc "${action}_containers" $devuuid))
        event_containers=($(get_docker_sc "${event}_${action}_containers" $devuuid))
        containers+=("${event_containers[@]}")
        if [ ! -z "${containers#}" ]; then
            info "Trying to ${action} containers"
            for i in "${containers[@]}"; do
                info "Looking up container with name ${i}"

                local found_container=$(docker container inspect -f {{.Id}} "${i}" || echo "")
                if [ ! -z "${found_container}" ]; then
                    info "Found '${found_container}'. Doing '${action}' now..."

                    case "$action" in
                    'restart')
                        docker restart ${found_container}
                        ;;
                    'start')
                        docker start ${found_container}
                        ;;
                    'stop')
                        docker stop ${found_container}
                        ;;
                    'remove')
                        docker stop ${found_container} && docker rm ${found_container}
                        ;;
                    *)
                        error "error: unsupported action ($action)"
                        exit 1
                        ;;
                    esac

                    if [ $? -eq 0 ]; then
                        info "Doing ${action} container '${found_container}' was successful"
                    else
                        error " > /proc/1/fd/1 2>/proc/1/fd/2
            Something went wrong while doing '${action}' '${found_container}'
            Please check health of containers and consider doing '${action}' them manually.
            "
                    fi
                else
                    error "Container '${i}' could not be found. Omitting container..."
                fi
            done

            info "Container '${action}' process done."
        fi
    done
}

action_services() {
    local devuuid=$1
    local event=$( [ "${ACTION}" = "remove" ] && echo 'unmount' || echo 'mount' )
    declare -a services
    declare -a actions=(update)

    for action in ${actions[@]}; do
        services=($(get_docker_sc "${action}_services" $devuuid))
        event_services=($(get_docker_sc "${event}_${action}_services" $devuuid))
        services+=("${event_services[@]}")
        if [ ! -z "${services#}" ]; then
            info "Trying to ${action} services"

            for i in "${services[@]}"; do
                info "Looking up service with name ${i}"

                local found_service=$(docker service inspect -f {{.ID}} "${i}" || echo "")
                if [ ! -z "${found_service}" ]; then
                    info "Found '${found_service}'. Running ${action} now..."

                    case "$action" in
                    'update')
                        docker service update --force ${found_service}
                        ;;
                    *)
                        error "error: unsupported action ($action)"
                        exit 1
                        ;;
                    esac

                    if [ $? -eq 0 ]; then
                        info "Restarting service '${found_service}' was successful"
                    else
                        error " > /proc/1/fd/1 2>/proc/1/fd/2
            Something went wrong while doing '${action}' '${found_service}'
            Please check health of services and their tasks and consider doing '${action}' them manually.
            "
                    fi
                else
                    error "Service '${i}' could not be found. Omitting service..."
                fi
            done

            info "Service '${action}' process done."
        fi
    done
}
