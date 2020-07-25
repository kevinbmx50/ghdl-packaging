#!/bin/sh

# Stop in case of error
set -e

enable_color() {
  ENABLECOLOR='-c '
  ANSI_RED="\033[31m"
  ANSI_GREEN="\033[32m"
  ANSI_YELLOW="\033[33m"
  ANSI_BLUE="\033[34m"
  ANSI_MAGENTA="\033[35m"
  ANSI_CYAN="\033[36;1m"
  ANSI_GRAY="\033[90m"
  ANSI_DARKCYAN="\033[36m"
  ANSI_NOCOLOR="\033[0m"
}

disable_color() { unset ENABLECOLOR ANSI_RED ANSI_GREEN ANSI_YELLOW ANSI_BLUE ANSI_MAGENTA ANSI_CYAN ANSI_DARKCYAN ANSI_NOCOLOR; }
enable_color

print_start() {
  if [ "x$2" != "x" ]; then
    COL="$2"
  elif [ "x$BASE_COL" != "x" ]; then
    COL="$BASE_COL"
  else
    COL="$ANSI_YELLOW"
  fi
  printf "${COL}${1}$ANSI_NOCOLOR\n"
}

gstart () {
  print_start "$@"
}
gend () {
  :
}
gblock () {
  gstart "$1"
    shift
    $@
  gend
}

[ -n "$CI" ] && {
  echo "INFO: set 'gstart' and 'gend' for CI"
  gstart () {
    printf '::group::'
    print_start "$@"
    SECONDS=0
  }

  gend () {
    duration=$SECONDS
    echo '::endgroup::'
    printf "${ANSI_GRAY}took $(($duration / 60)) min $(($duration % 60)) sec.${ANSI_NOCOLOR}\n"
  }
} || echo "INFO: not in CI"

#---

do_build () {
  if [ -z "$TARGET" ]; then
    printf "${ANSI_RED}Undefined TARGET!$ANSI_NOCOLOR"
    exit 1
  fi

  gstart 'Prepare /wrk'
    cp -vr "/src/$TARGET" /wrk
    cd /wrk
  gend

  gblock 'Install devel deps' pacman -Syu --noconfirm --noprogressbar --needed grep base-devel

  gstart 'Set permissions for nobody'
    chage -E -1 nobody
    chown -R nobody:nobody /wrk
    chgrp nobody /wrk
    chmod g+ws /wrk
    setfacl -m u::rwx,g::rwx /wrk
    setfacl -d --set u::rwx,g::rwx,o::- /wrk

    # FIXME: this should allow 'nobody' only, not ALL users
    echo 'ALL ALL=(ALL) NOPASSWD: /usr/sbin/pacman' >> /etc/sudoers
  gend

  gblock 'Build package' sudo -u nobody makepkg -sCLfc --skippgpcheck --noconfirm
  gblock 'List artifacts' ls -la

  gstart 'Copy artifacts'
    mkdir -p "/src/$TARGET/artifacts"
    cp ghdl*.pkg.tar.* PKGBUILD .gitignore "/src/$TARGET/artifacts/"
    if [ -d testsuite ]; then
      echo "Copying testsuite..."
      cp -r testsuite "/src/$TARGET/"
    fi
  gend
}

#---

do_test () {
  for PKG in artifacts/ghdl*.pkg.tar.*; do
    gstart "Install $PKG"
      pacman -U --noconfirm --noprogressbar --needed $PKG
    gend
    GHDL=ghdl ./testsuite/testsuite.sh
  done
}

#---

case "$1" in
  build)
    do_build
  ;;
  test)
    do_test
  ;;
  *)
    archdir="$(realpath $(dirname $0))"

    printf "${ANSI_MAGENTA}Run 'build' in a container\n$ANSI_NOCOLOR"
    docker run --rm -e CI \
      -e BASE_COL="$ANSI_BLUE" \
      -e TARGET \
      -v /"$archdir"://src -w //src/ \
      ghdl/build:archlinux ./run.sh build

    gblock 'PKGBUILD diff' git diff "${archdir}/${TARGET}/PKGBUILD"

    if [ -d "${archdir}/${TARGET}"/testsuite ]; then
      printf "${ANSI_MAGENTA}Run 'test' in a container\n$ANSI_NOCOLOR"
      docker run --rm -e CI \
        -v /"$archdir"://src -w "//src/$TARGET" \
        ghdl/build:archlinux ../run.sh test
    fi

    sudo chown -R $USER:$USER "${archdir}/${TARGET}"
  ;;
esac
