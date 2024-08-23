{
  pkgs ? import <nixpkgs> { },
  bash3 ? pkgs.callPackage ./bash/3.nix { },
  ...
}:
pkgs.mkShellNoCC {
  shellHook = ''
    export PATH="$PWD/scripts:$PATH"
  '';

  packages =
    (with pkgs; [
      nodePackages.bash-language-server
      shellcheck
      shellharden
      checkbashisms
      shfmt
      zsh
      yaml-language-server
      hyperfine
      gitmux
    ])
    ++ [ bash3 ];
}
