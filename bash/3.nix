{
  lib,
  stdenv,
  buildPackages,
  fetchurl,
  bison,

  interactive ? false,
  readline,
  withDocs ? false,
  texinfo,
  forFHSEnv ? false,
}:

assert interactive -> readline != null;

let
  realName = "bash-3.2.57";

  upstreamPatches = import ./bash-3.2-patches.nix (
    nr: sha256:
    fetchurl {
      url = "mirror://gnu/bash/bash-3.2-patches/bash32-${nr}";
      inherit sha256;
    }
  );
in

stdenv.mkDerivation rec {
  pname = "bash3${lib.optionalString interactive "-interactive"}";
  version = "3.2${patch_suffix}";
  patch_suffix = "p${toString (builtins.length upstreamPatches)}";
  name = "${realName}-p${toString (builtins.length patches)}";

  src = fetchurl {
    url = "mirror://gnu/bash/bash-${lib.removeSuffix patch_suffix version}.tar.gz";
    sha256 = "sha256-JsmQJbWeMHeTALaK23ZPgkl00mek18wbNH0Uojk/n7Q=";
  };

  hardeningDisable =
    [ "format" ]
    # bionic libc is super weird and has issues with fortify outside of its own libc, check this comment:
    # https://github.com/NixOS/nixpkgs/pull/192630#discussion_r978985593
    # or you can check libc/include/sys/cdefs.h in bionic source code
    ++ lib.optional (stdenv.hostPlatform.libc == "bionic") "fortify";

  outputs = [
    "out"
    # "dev"
    # "man"
    # "doc"
    # "info"
  ];

  env.NIX_CFLAGS_COMPILE =
    ''
      -DSYS_BASHRC="/etc/bashrc"
      -DSYS_BASH_LOGOUT="/etc/bash_logout"
    ''
    + lib.optionalString (!forFHSEnv) ''
      -DDEFAULT_PATH_VALUE="/no-such-path"
      -DSTANDARD_UTILS_PATH="/no-such-path"
    ''
    + ''
      -DNON_INTERACTIVE_LOGIN_SHELLS
      -DSSH_SOURCE_BASHRC
    '';

  patchFlags = "-p0";

  patches = upstreamPatches;

  configureFlags =
    [
      "PACKAGE_NAME=bash3"
      # At least on Linux bash memory allocator has pathological performance
      # in scenarios involving use of larger memory:
      #   https://lists.gnu.org/archive/html/bug-bash/2023-08/msg00052.html
      # Various distributions default to system allocator. Let's nixpkgs
      # do the same.
      "--without-bash-malloc"
      (if interactive then "--with-installed-readline" else "--disable-readline")
    ]
    ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "bash_cv_job_control_missing=nomissing"
      "bash_cv_sys_named_pipes=nomissing"
      "bash_cv_getcwd_malloc=yes"
      # This check cannot be performed when cross compiling. The "yes"
      # default is fine for static linking on Linux (weak symbols?) but
      # not with OpenBSD, when it does clash with the regular `getenv`.
      "bash_cv_getenv_redef=${if !(with stdenv.hostPlatform; isStatic && isOpenBSD) then "yes" else "no"}"
    ]
    ++ lib.optionals stdenv.hostPlatform.isCygwin [
      "--without-libintl-prefix"
      "--without-libiconv-prefix"
      "--with-installed-readline"
      "bash_cv_dev_stdin=present"
      "bash_cv_dev_fd=standard"
      "bash_cv_termcap_lib=libncurses"
    ]
    ++ lib.optionals (stdenv.hostPlatform.libc == "musl") [ "--disable-nls" ];

  strictDeps = true;
  # Note: Bison is needed because the patches above modify parse.y.
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  nativeBuildInputs = [
    bison
  ] ++ lib.optional withDocs texinfo ++ lib.optional stdenv.hostPlatform.isDarwin stdenv.cc.bintools;

  buildInputs = lib.optional interactive readline;

  # Bash randomly fails to build because of a recursive invocation to
  # build `version.h'.
  enableParallelBuilding = false;

  makeFlags =
    [ "Program=bash3" ]
    ++ lib.optionals stdenv.hostPlatform.isCygwin [
      "LOCAL_LDFLAGS=-Wl,--export-all,--out-implib,libbash.dll.a"
      "SHOBJ_LIBS=-lbash"
    ];

  postInstall = ''
    # Add an `sh' -> `bash' symlink.
    ln -s bash "$out/bin/sh"
  '';

  postFixup =
    if interactive then
      ''
        substituteInPlace "$out/bin/bashbug" \
          --replace '#!/bin/sh' "#!$out/bin/bash"
      ''
    # most space is taken by locale data
    else
      ''
        rm -rf "$out/share" "$out/bin/bashbug"
      '';

  meta = {
    homepage = "http://www.gnu.org/software/bash/";
    description =
      "GNU Bourne-Again Shell, the de facto standard shell on Linux"
      + (if interactive then " (for interactive use)" else "");

    longDescription = ''
      Bash is the shell, or command language interpreter, that will
      appear in the GNU operating system.  Bash is an sh-compatible
      shell that incorporates useful features from the Korn shell
      (ksh) and C shell (csh).  It is intended to conform to the IEEE
      POSIX P1003.2/ISO 9945.2 Shell and Tools standard.  It offers
      functional improvements over sh for both programming and
      interactive use.  In addition, most sh scripts can be run by
      Bash without modification.
    '';

    license = lib.licenses.gpl2;

    maintainers = [ ];
  };

  passthru = {
    shellPath = "/bin/bash";
  };
}
