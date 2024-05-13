#!/bin/bash -e

export PREFIX=${CONDA_PREFIX}
export CMAKE_PREFIX_PATH=${PREFIX}:${CMAKE_PREFIX_PATH}

# clone all projects
function lpm_clone {
    while read -r source
    do
        IFS='	' read -r -a split <<< "${source}"
        NAME="${split[0]}"
        URL="${split[1]}"
        REVISION="${split[2]}"
        if [[ ! -d ${NAME} ]]
        then
            echo "[LPM] Clone ${NAME}"
            git clone --recursive "${URL}" "${NAME}"
            git -C "${NAME}" remote set-url lpm "${URL}"
        fi
        if [[ -f lpm.lock ]]
        then
	        URL_LOCK="$(grep "${NAME}" lpm.lock | cut -f2)"
            COMMIT_LOCK="$(grep "${NAME}" lpm.lock | cut -f3)"
            echo "[LPM] Read commit ${COMMIT_LOCK} for ${NAME}"
	        git -C "${NAME}" remote set-url lpm "${URL_LOCK}"
	        git -C "${NAME}" fetch lpm
	        git -C "${NAME}" checkout "${COMMIT_LOCK}"
        else
            git -C "${NAME}" checkout "${REVISION}"
	        git pull
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
        REVISION="${split[2]}"
        echo "[LPM] Update ${NAME}"
        git -C "${NAME}" remote set-url lpm "${URL}"
        git -C "${NAME}" fetch lpm
        git -C "${NAME}" checkout "${REVISION}"
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
	    CMAKE_ARGS=""
        if [[ "${#split[@]}" -eq 4 ]]
        then
            CMAKE_ARGS="${split[3]}"
        fi
        echo "[LPM] Lock ${NAME}"
        set +e
        {
            URL_LOCK="$(git -C "${NAME}" remote get-url $(git -C "${NAME}" rev-parse --abbrev-ref --symbolic-full-name @{u} | cut -d'/' -f1))"
        } || {
            URL_LOCK="$(git -C "${NAME}" remote get-url lpm)"
        } || {
            URL_LOCK="$(git -C "${NAME}" remote get-url origin)"
        }
        set -e
        echo "{LPM} locked ${URL_LOCK}"
        REV_LOCK="$(git -C "${NAME}" rev-parse HEAD)"
        echo "${NAME}	${URL_LOCK}	${REV_LOCK}	${CMAKE_ARGS}" >> lpm.tmp
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
        cmake -S "${NAME}" -B "${NAME}/build_${TYPE}" "-DCMAKE_INSTALL_PREFIX=${PREFIX} -DCMAKE_BUILD_TYPE=${TYPE} -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER=clang++" ${CMAKE_ARGS}
        cmake --build "${NAME}/build_${TYPE}"
        cmake --build "${NAME}/build_${TYPE}" -t test
        cmake --build "${NAME}/build_${TYPE}" -t install
    done < lpm.tsv
}
function lpm_build_release {
    TYPE="Release"
    lpm_build
}
function lpm_build_debug {
    TYPE="Debug"
    lpm_build
}

# remove build caches
function lpm_clean {
    while read -r source
    do
        IFS='	' read -r -a split <<< "${source}"
        NAME="${split[0]}"
        echo "[LPM] Clean ${NAME}"
        rm -rf "${NAME}/build_*"
    done < lpm.tsv
}

if [[ ! -f lpm.tsv ]]
then
    echo "Error: No lpm.tsv file here. Are you in the right folder ?"
    exit 1
fi

if [[ ! -f lpm.lock ]]
then
    echo "Warning: lpm.lock not found. Using only lpm.tsv configuration file"
fi

case $1 in
    "build_release"|"build") lpm_build_release ;;
    "build_debug") lpm_build_debug ;;
    "clean") lpm_clean ;;
    "clone") lpm_clone ;;
    "update") lpm_update ;;
    "lock") lpm_lock ;;
    *)
        echo "Error: valid commands are: build_release build_debug build clean clone update lock"
        exit 2
        ;;
esac
