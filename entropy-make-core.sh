#!/usr/bin/env bash
set -e
MK_BASHRCNAME="${BASH_SOURCE[0]}"
while [ -h "$MK_BASHRCNAME" ]; do # resolve $MK_BASHRCNAME until the file is no longer a symlink
    MK_BASHSRCDIR="$( cd -P "$( dirname "$MK_BASHRCNAME" )" >/dev/null && pwd )"
    MK_BASHRCNAME="$(readlink "$MK_BASHRCNAME")"

    # if $MK_BASHRCNAME was a relative symlink, we need to resolve it relative
    # to the path where the symlink file was located
    [[ $MK_BASHRCNAME != /* ]] && MK_BASHRCNAME="$MK_BASHSRCDIR/$MK_BASHRCNAME"
done
MK_BASHSRCDIR="$( cd -P "$( dirname "$MK_BASHRCNAME" )" >/dev/null && pwd )"
MK_SRCDIR="${MK_BASHSRCDIR}/src"
if [[ $MK_TESTP = 'test' ]] || [[ $1 = 'test' ]]; then
    export MK_TESTP=1
else
    export MK_TESTP=0
fi

# Multi threads 'xz' enc/dec task for fasting the procedure See:
# https://stackoverflow.com/a/33441796
export XZ_DEFAULTS="-T 0"

MK_FFVER=118.0.2
MK_FFSRCDIR="${MK_SRCDIR}/firefox-${MK_FFVER}"
MK_FFTARBALL_BASENAME="firefox-${MK_FFVER}.source.tar.xz"
MK_FFTARBALL_FILE="${MK_SRCDIR}/${MK_FFTARBALL_BASENAME}"
MK_FFTARBALL_FILE_SHAHASH='89626520f2f0f782f37c074b94690e0f08dcf416be2b992f4aad68df5d727b21'
MK_FFTARBALL_E_BASENAME="entropy-patched-firefox-${MK_FFVER}.source.tar.xz"
MK_FFTARBALL_E_FILE="${MK_SRCDIR}/${MK_FFTARBALL_E_BASENAME}"
MK_FFSRCURI="https://archive.mozilla.org/pub/firefox/\
releases/${MK_FFVER}/source/${MK_FFTARBALL_BASENAME}"

if [[ -e $MK_FFSRCDIR ]] && [[ $MK_TESTP -eq 0 ]]; then
    echo 'remove old build tree ...'
    rm -rf "$MK_FFSRCDIR"
fi

i=0
while [[ ! -f $MK_FFTARBALL_FILE ]] || \
          { echo "firefox tarball shahash verifying ..." ; \
            [[ ! $(sha256sum "$MK_FFTARBALL_FILE" | cut -d' ' -f 1) = "$MK_FFTARBALL_FILE_SHAHASH" ]] ;
          }
do
    if [[ -f $MK_FFTARBALL_FILE ]] ; then rm -f "$MK_FFTARBALL_FILE" ; fi
    let i++ || :
    echo "[${i}th] downloading source tarball ..."
    curl -L "$MK_FFSRCURI" -o "$MK_FFTARBALL_FILE"
done

if [[ ! -d $MK_FFSRCDIR ]]; then
    echo "untarring ${MK_FFTARBALL_FILE} ..."
    tar -Jxf "$MK_FFTARBALL_FILE" -C "$MK_SRCDIR"
fi

MK_PATCHDIR="${MK_BASHSRCDIR}/entropy-spec/patches"
while IFS= read i ; do
    j="${i%/*}" ; k="${i##*/}"
    if [[ $k =~ \.espec$ ]] ; then
        (
            k="${k%.espec}"
            set -ex
            cd "${MK_FFSRCDIR}/${j}/"
            if [[ $MK_TESTP -eq 0 ]] ; then
                diff "$k" "${MK_PATCHDIR}/${j}/${k}" >/dev/null
            fi
            rm "$k" && cp -a "${MK_PATCHDIR}/${i}" "$k"
        )
    fi
done < <(set -e; cd "${MK_PATCHDIR}"; find -type f)

if [[ -e $MK_FFTARBALL_E_FILE ]] ; then rm -f "$MK_FFTARBALL_E_FILE" ; fi
echo "Generate patched source tarball ..."
( set -e
  i="${MK_FFSRCDIR%/}"
  j="${i##*/}"
  i="${i%/*}"
  cd "${i}/"
  tar -Jcf "${MK_FFTARBALL_E_FILE}" "$j"
)

set -x

export MOZ_BUILD_DATE="$(printf "%(%Y%m%d%H%M%S)T\n")"
# change default moz state dir '~/.mozbuild' to our spec, see more of docstring under
# 'build/mach_initialize.py'
mk_mozbuild_state_path_base='.mozbuild'
export MOZBUILD_STATE_PATH="${MK_FFSRCDIR}/${mk_mozbuild_state_path_base}"

mk_edist_dir="${MK_FFSRCDIR}/entropy-dist"
mk_ver="$(cat "${MK_FFSRCDIR}/browser/config/version.txt")"
mk_eflver="$(cat "${MK_FFSRCDIR}/browser/config/version_display.txt")"
mk_gpgverifyID='42EBF24476885D91'
mk_platform="$(uname -m)"
mk_objdir="${MK_FFSRCDIR}/obj-${mk_platform}-pc-linux-gnu"
mk_distdir="${MK_FFSRCDIR}/obj-${mk_platform}-pc-linux-gnu/dist"
mk_gitrev=''

[[ -f "${MK_FFSRCDIR}/mozconfig" ]] && rm -f "${MK_FFSRCDIR}/mozconfig"
if [[ -e ${MK_FFSRCDIR}/.git ]] ; then
    if [[ $MK_TESTP -eq 0 ]] ; then
        git -C "$MK_FFSRCDIR" clean -xfd
    fi
    git -C "$MK_FFSRCDIR" submodule deinit --force --all
    git -C "$MK_FFSRCDIR" submodule update --init --recursive
    mk_gitrev="$(git -C "$MK_FFSRCDIR" describe --tags || echo '')"
    if [[ $mk_gitrev =~ ^(entropy-)?v[0-9]+\. ]] && \
           [[ ! $mk_gitrev =~ '-'[0-9]+-g.+$ ]]
    then
        :
    else
        mk_gitrev="$(git -C "$MK_FFSRCDIR" rev-parse --short HEAD)"
        mk_eflver="${mk_eflver}_entropy_git:${mk_gitrev}"
    fi
fi
if [[ -e "${mk_edist_dir}" ]] ; then rm -rvf "$mk_edist_dir" ; fi
if [[ $MK_TESTP -eq 0 ]] && [[ -e "${mk_objdir}" ]] ; then  rm -rvf "$mk_objdir"; fi


function mk_func_add_mozconf ()
{
    echo "$1" >> "${MK_FFSRCDIR}/mozconfig"
}

function mk_func_call_marh ()
{
    if [[ MK_TESTP -eq 1 ]] ; then
        echo "./mach $*"
    else
        ./mach "$@"
    fi
}

mk_func_add_mozconf "ac_add_options --disable-bootstrap"
# Since issue of https://bugzilla.mozilla.org/show_bug.cgi?id=1759544
# , we can not build ff use moziila official sccache without vcs
# controlled source tree.
#
#mk_func_add_mozconf 'ac_add_options --without-wasm-sandboxed-libraries'
#mk_func_add_mozconf "mk_add_options 'export RUSTC_WRAPPER=${MOZBUILD_STATE_PATH}/sccache/sccache'"
#mk_func_add_mozconf "mk_add_options 'export CCACHE_CPP2=yes'"
#mk_func_add_mozconf "ac_add_options --with-ccache=${MOZBUILD_STATE_PATH}/sccache/sccache"

mk_func_add_mozconf "ac_add_options --enable-application=browser"
mk_func_add_mozconf "ac_add_options --enable-proxy-bypass-protection"
mk_func_add_mozconf "ac_add_options --enable-unverified-updates"
mk_func_add_mozconf "ac_add_options --enable-release"
mk_func_add_mozconf "ac_add_options --enable-linker=lld"
mk_func_add_mozconf "ac_add_options --disable-elf-hack"
mk_func_add_mozconf "ac_add_options --enable-official-branding"
mk_func_add_mozconf "ac_add_options --enable-update-channel=release"
mk_func_add_mozconf "ac_add_options --with-distribution-id=org.archlinux"
mk_func_add_mozconf "ac_add_options --with-unsigned-addon-scopes=app,system"
mk_func_add_mozconf "ac_add_options --allow-addon-sideload"
mk_func_add_mozconf "mk_add_options 'export MOZILLA_OFFICIAL=1'"
mk_func_add_mozconf "mk_add_options 'export MOZ_APP_REMOTINGNAME=firefox'"
mk_func_add_mozconf "ac_add_options --with-google-location-service-api-keyfile=${MK_BASHSRCDIR@Q}/entropy-spec/google_api_key"
mk_func_add_mozconf "ac_add_options --with-google-safebrowsing-api-keyfile=${MK_BASHSRCDIR@Q}/entropy-spec/google_api_key"
mk_func_add_mozconf "ac_add_options --with-mozilla-api-keyfile=${MK_BASHSRCDIR@Q}/entropy-spec/mozilla_api_key"
# mk_func_add_mozconf "ac_add_options --enable-alsa"
# mk_func_add_mozconf "ac_add_options --enable-jack"
mk_func_add_mozconf "ac_add_options --disable-crashreporter"
mk_func_add_mozconf "ac_add_options --disable-tests"
mk_func_add_mozconf 'ac_add_options --disable-updater'
if [[ $MK_OPT_NO_OPTIMIZATION != '1' ]] ; then
    mk_func_add_mozconf 'ac_add_options MOZ_PGO=1'
    mk_func_add_mozconf "ac_add_options --enable-lto"
    mk_func_add_mozconf "ac_add_options --enable-hardening"
    mk_func_add_mozconf 'ac_add_options --enable-optimize="-O3"'
    # this may cause build failed due to: https://github.com/rust-lang/rust/issues/116137
    #mk_func_add_mozconf "ac_add_options --enable-rust-simd"
    mk_func_add_mozconf "export RUSTC_OPT_LEVEL=2"
else
    :
    # FIXME: Do not explicitly use '--disable-optimize' option or may
    # cause build linkage failure.
    #
    #mk_func_add_mozconf 'ac_add_options --disable-optimize'
fi
mk_func_add_mozconf "export MOZ_INCLUDE_SOURCE_INFO=1"
mk_func_add_mozconf "MOZ_REQUIRE_SIGNING="
mk_func_add_mozconf "MOZ_DATA_REPORTING="
mk_func_add_mozconf "MOZ_TELEMETRY_REPORTING="
if [[ $(lsb_release -si) = 'Arch' ]] ; then
    mk_func_add_mozconf 'ac_add_options --with-wasi-sysroot=/usr/share/wasi-sysroot'
fi

test -f "${MK_FFSRCDIR}/browser/app/profile/firefox.js"

cat >>"${MK_FFSRCDIR}/browser/app/profile/firefox.js" <<EOF

// * Entropy build spec
// ** Telemetry disable from Floorp spec
pref("services.sync.telemetry.maxPayloadCount", "0", locked);
pref("services.sync.telemetry.submissionInterval", "0", locked);
pref("toolkit.telemetry.archive.enabled", false, locked);
pref("toolkit.telemetry.bhrPing.enabled", false, locked);
pref("toolkit.telemetry.enabled", false, locked);
pref("toolkit.telemetry.firstShutdownPing.enabled", false, locked);
pref("toolkit.telemetry.geckoview.streaming", false, locked);
pref("toolkit.telemetry.newProfilePing.enabled", false, locked);
pref("toolkit.telemetry.pioneer-new-studies-available", false, locked);
pref("toolkit.telemetry.reportingpolicy.firstRun", false, locked);
pref("toolkit.telemetry.server", "", locked);
pref("toolkit.telemetry.shutdownPingSender.enabled", false, locked);
pref("toolkit.telemetry.shutdownPingSender.enabledFirstSession", false, locked);
pref("toolkit.telemetry.testing.overrideProductsCheck", false, locked);
pref("toolkit.telemetry.unified", false, locked);
pref("toolkit.telemetry.updatePing.enabled", false, locked);
pref("privacy.trackingprotection.origin_telemetry.enabled", false, locked);

// ** Misc.
pref("extensions.getAddons.showPane", false);
pref("extensions.pocket.enabled", false);
pref("xpinstall.signatures.required", false);
//Firefox調査を無効化
pref("app.shield.optoutstudies.enabled", false, locked);
//拡張機能の推奨を削除
pref("browser.discovery.enabled", false);
//クラッシュレポートの自動送信無効
pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
//http 通信時、Floorp は絶対にhttp:// をURLバーから隠しません
pref("browser.urlbar.trimURLs", false);

// ** Privacy
//プライバシー機能をオンにし、テレメトリー採取を無効化します。
pref("privacy.trackingprotection.origin_telemetry.enabled", false, locked);
pref("privacy.userContext.enabled", true);
pref("privacy.userContext.ui.enabled", true);
pref("trailhead.firstrun.branches", "", locked);
pref("extensions.webcompat-reporter.enabled", false);

pref("extensions.htmlaboutaddons.recommendations.enabled", false, locked);
pref("datareporting.policy.dataSubmissionEnable", false, locked);
pref("datareporting.healthreport.uploadEnabled", false, locked);
pref("toolkit.legacyUserProfileCustomizations.script", false);

// ** Theme Default Options
// userchrome.css usercontent.css activate
pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
EOF

cd "${MK_FFSRCDIR}"/

# for a official build, firefox need X display for batch of web render
# test, thus we exposed a virtual DISPLAY which will not pollute which
# DISPLAY our session used.
pkill -x Xvfb || :
! command -v Xvfb &>/dev/null && \
    echo "\
virtual X frame buffer command Xvfb is not found in your PATH." \
    && exit 1
Xvfb :20 -screen 0 1024x768x24 &
mk_xvfb_procid=$!
echo "Waiting for xvfb initialization finished ..."
sleep 2
if ! ps -p $mk_xvfb_procid &>/dev/null ; then
    echo "Xvfb init fatal" ; exit 1
else
    export DISPLAY=:20
    # since firfox may prefer test with wayland, but we prefer use
    # headless virtual X display.
    unset -v WAYLAND_DISPLAY
fi

ulimit -n 4096
export MOZ_NOSPAM=1
if ! mk_func_call_marh build ; then
    # try twice build for first fail which may caused by OOM
    mk_func_call_marh build
fi

mk_func_call_marh package

if ps -p "$mk_xvfb_procid" &>/dev/null ; then
    kill "$mk_xvfb_procid"
fi

mkdir -p "${mk_edist_dir}/"
(
    set -e
    if [[ $MK_TESTP -eq 0 ]]; then
        cd "$mk_distdir"
        for i in firefox-*.bz2 ; do
            mv "$i" "${mk_edist_dir}/${i/"$mk_ver"/"$mk_eflver"}"
        done
        for i in firefox-*.zip ; do
            mv "$i" "${mk_edist_dir}/${i/"$mk_ver"/"$mk_eflver"}"
        done
        for i in firefox-*.txt ; do
            mv "$i" "${mk_edist_dir}/${i/"$mk_ver"/"$mk_eflver"}"
        done
    fi

    # archive source
    [[ ! -e ${mk_edist_dir}/${MK_FFTARBALL_E_BASENAME} ]]
    mv -v "$MK_FFTARBALL_E_FILE" "${mk_edist_dir}/"
)

(
    set -ex
    [[ ! -e "${mk_edist_dir}/${mk_mozbuild_state_path_base%/}.tar.xz" ]]
    i="${MOZBUILD_STATE_PATH%/}";
    j="${i%/*}"
    i="${i##*/}"
    declare -a arr=()
    for k in toolchains indices ; do
        if [[ -d ${MOZBUILD_STATE_PATH}/$k ]] ; then
            arr+=("${i}/${k}")
        fi
    done
    if [[ -n "${arr[*]}" ]] ; then
        tar -Jcf \
            "${mk_edist_dir}/${mk_mozbuild_state_path_base%/}.tar.xz" \
            -C "$j" "${arr[@]}"
    fi
)

if [[ -e ${MK_FFSRCDIR}/.git ]] ; then
    echo "Archiving source tree ..."
    git archive --format=tar \
        --output="${mk_edist_dir}/firefox-${mk_eflver}.src.tar" \
        HEAD
    echo "Archiving source submodules tree recursively ..."
    git submodule --quiet foreach --recursive \
        'git archive --format=tar --prefix="${displaypath}/" -o __submodule__.tar HEAD'
    echo "Combination of source and submodules tree ..."
    # use force-local option to allow colon char in archive name: see
    # https://superuser.com/questions/1720172/what-does-tar-cannot-connect-to-resolve-failed-mean
    git submodule --quiet foreach --recursive \
        "cd '${mk_edist_dir}'                           && \
tar --concatenate --force-local                            \
--file='firefox-${mk_eflver}.src.tar'                       \
\"${MK_FFSRCDIR}/\${displaypath}/__submodule__.tar\"  && \
rm -fv \"${MK_FFSRCDIR}/\${displaypath}/__submodule__.tar\""
    cd "${mk_edist_dir}"
    echo "Gzip srouce archive ..."
    xz "firefox-${mk_eflver}.src.tar"
fi

(
    set -ex
    # we should either populate cargo caches since moz build relying
    # on various rust deps hosted in github.com which are not included
    # in source tarball.
    declare -a rust_hs=()
    for i in '.cargo' '.rustup' ; do
        if [[ -d ${HOME}/${i} ]] ; then
            rust_hs+=( "${i}")
        fi
    done
    if [[ $MK_VIA_DOCKER = 'true' ]] && [[ -n "${rust_hs[*]}" ]]; then
        [[ ! -e ${mk_edist_dir}/RUST_TOOLCHAIN_CACHE.tar.xz ]]
        cd "${HOME}"
        tar -Jcf "${mk_edist_dir}/RUST_TOOLCHAIN_CACHE.tar.xz" "${rust_hs[@]}"
    fi
)

cd "${mk_edist_dir}"
cat <<EOF > README.org
#+title: Firefox ${mk_eflver} release note:
#+date: $(printf '%(%Y%m%d%H%M%S)T\n')
#+author: Entropy

This release of firefox-${MK_FFVER} is my self built with mozconf of:

#+begin_example
$(cat "${MK_FFSRCDIR}/mozconfig")
#+end_example

Which are for the sake of doing most compiler optimization and privacy
prefs specification.
$( if [[ $MK_VIA_DOCKER = 'true' ]] ; then
      echo ;
      echo "\
To recompile the source, may used preserved rust toolchain cache
(RUST_TOOLCHAIN_CACHE.tar.xz) for '${MK_FFTARBALL_BASENAME}' at built
time. Which simply extracted it and migrate the '.cargo' directory to
\$HOME root or copy its contents to anywhere your current \$CARGO_HOME
specified in, thus same for '.rustup' for \$RUSTUP_HOME."; echo ' ';
   fi; )
To check this distribution validation, please check the
'sha256sum.log'.
EOF

echo "Generate sha256sum hash log for distributions ..."
if [[ $MK_TESTP -eq 1 ]] ; then
    rm -f sha256sum.log*
fi
mk_dist_shahash="$(find . -type f -print0 | xargs --null sha256sum -b)"
echo "$mk_dist_shahash" > ./sha256sum.log
if [[ -n $mk_gpgverifyID ]] && \
       gpg --list-secret-keys \
           "$mk_gpgverifyID" >/dev/null 2>&1
then
    gpg --detach-sign --armor \
        -u "$mk_gpgverifyID"    \
        -o "sha256sum.log.asc" "sha256sum.log"
fi

# finally dist tarball generation
MK_DISTTARBALL="${MK_BASHSRCDIR}/dist/entropy-firefox-${mk_eflver}.tar.xz"
if [[ -e $MK_DISTTARBALL ]] ; then rm -f "$MK_DISTTARBALL" ; fi
tar -Jcf "${MK_DISTTARBALL}" \
    -C "${MK_FFSRCDIR}/" entropy-dist
