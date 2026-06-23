#!/bin/sh
# Entrypoint for the AlbFetcharr production image.
#
# Runs the container process as the requested UID:GID (via gosu) after fixing up
# ownership of the writable paths, then dispatches to either the web server
# (default) or a one-shot CLI subcommand:
#   <no args>           -> gunicorn web UI/API on :${ALBFETCHARR_PORT:-5000}
#   wanted [args]       -> download every wanted album, import into Lidarr
#   download <url> ...  -> download a single album by URL
# (see the deploy README "CLI mode" and the backend `albfetcharr` CLI.)

echo "Setting umask to ${UMASK:-022}"
umask "${UMASK:-022}"
echo "Creating download directory (${DOWNLOAD_DIR})"
mkdir -p "${DOWNLOAD_DIR}"

setup_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$(id -g)" -eq 0 ]; then
        if [ "${UID}" -eq 0 ]; then
            echo "Warning: running as root is not recommended — check the UID environment variable"
        fi
        if [ "${CHOWN_DIRS:-true}" != "false" ]; then
            echo "Changing ownership of app, download and config directories to ${UID}:${GID}"
            # /config holds the settings DB + optional oauth/cookies; chown only if mounted.
            chown -R "${UID}":"${GID}" /app "${DOWNLOAD_DIR}"
            [ -d /config ] && chown -R "${UID}":"${GID}" /config
        fi
        echo "Running as user ${UID}:${GID}"
        EXEC_PREFIX="gosu ${UID}:${GID}"
    else
        echo "User set by docker; running as $(id -u):$(id -g)"
        EXEC_PREFIX=""
    fi
}

setup_user

case "$1" in
    wanted)
        shift
        exec ${EXEC_PREFIX} python -m albfetcharr wanted "$@"
        ;;
    download)
        shift
        exec ${EXEC_PREFIX} python -m albfetcharr download "$@"
        ;;
    *)
        exec ${EXEC_PREFIX} gunicorn "albfetcharr.web.app:create_app()" \
            --bind "0.0.0.0:${ALBFETCHARR_PORT:-5000}" \
            --workers 1 \
            --threads 4 \
            --timeout 300 \
            --access-logfile - \
            --error-logfile -
        ;;
esac
