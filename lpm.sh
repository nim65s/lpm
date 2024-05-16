#!/bin/bash -e

export PREFIX=./install
export CMAKE_PREFIX_PATH=${PREFIX}:${CMAKE_PREFIX_PATH}

# clone all projects
function lpm_clone {
    while read -r source
    do
        IFS='	' read -r -a split <<< "${source}"
        NAME="${split[0]}"
        URL="${split[1]}"
        BRANCH="${split[2]}"
        if [[ ! -d ${NAME} ]]
        then
            echo "[LPM] Clone ${NAME}"
            git clone --recursive --branch "${BRANCH}" "${URL}" "${NAME}"
        fi
        ACTION="$(git -C "${NAME}" remote -v | grep -q '^lpm' && echo set-url || echo add)"
        git -C "${NAME}" remote "${ACTION}" lpm "${URL}"
        if [[ -f lpm.lock ]]
        then
            COMMIT="$(grep "^${NAME}	" lpm.lock | cut -f2)"
            git -C "${NAME}" checkout "${COMMIT}"
        else
            git -C "${NAME}" checkout "${BRANCH}"
        fi
    done < lpm.tsv
}

# update all repos
function lpm_update {
    while read -r source
    do
        IFS='	' read -r -a split <<< "${source}"
        NAME="${split[0]}"
        URL="${split[1]}"
        BRANCH="${split[2]}"
        echo "[LPM] Update ${NAME}"
        git -C "${NAME}" remote set-url lpm "${URL}"
        git -C "${NAME}" fetch lpm "${BRANCH}"
        git -C "${NAME}" checkout "${BRANCH}"
        git -C "${NAME}" reset --hard "lpm/${BRANCH}"
    done < lpm.tsv
    lpm_lock
}

# save the current revision from each project in lock file
function lpm_lock {
    rm -f lpm.tmp
    while read -r source
    do
        IFS='	' read -r -a split <<< "${source}"
        NAME="${split[0]}"
        URL="${split[1]}"
        BRANCH="${split[2]}"
        echo "[LPM] Lock ${NAME}"
        REV="$(git -C "${NAME}" rev-parse HEAD)"
        echo "${NAME}	${REV}" >> lpm.tmp
    done < lpm.tsv
    mv lpm.tmp lpm.lock
}

# build/test/install all projects
function lpm_build {
    while read -r source
    do
        IFS='	' read -r -a split <<< "${source}"
        NAME="${split[0]}"
        URL="${split[1]}"
        BRANCH="${split[2]}"
        CMAKE_ARGS=""
        if [[ "${#split[@]}" -eq 4 ]]
        then
            CMAKE_ARGS="${split[3]}"
        fi
        echo "[LPM] Build ${NAME}"
        cmake -S "${NAME}" -B "${NAME}/build" "-DCMAKE_INSTALL_PREFIX=${PREFIX}" ${CMAKE_ARGS}
        cmake --build "${NAME}/build"
        cmake --build "${NAME}/build" -t test
        cmake --build "${NAME}/build" -t install
    done < lpm.tsv
}

# remove build caches
function lpm_clean {
    while read -r source
    do
        IFS='	' read -r -a split <<< "${source}"
        NAME="${split[0]}"
        echo "[LPM] Clean ${NAME}"
        rm -rf "${NAME}/build"
    done < lpm.tsv
}

if [[ ! -f lpm.tsv ]]
then
    echo "Error: No lpm.tsv file here. Are you in the right folder ?"
    exit 1
fi

if [[ ! -f lpm.lock ]]
then
    echo "Warning: lpm.lock not found. Creating it..."
    lpm_clone
    lpm_lock
fi

case $1 in
    ""|"build") lpm_build ;;
    "clean") lpm_clean ;;
    "clone") lpm_clone ;;
    "update") lpm_update ;;
    "lock") lpm_lock ;;
    *)
        echo "Error: valid commands are: build clean clone update lock. build is the default"
        exit 2
        ;;
esac
