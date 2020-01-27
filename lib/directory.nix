{ pkgs }:

let
  jupyter = pkgs.python3Packages.jupyterlab;

  nodeBin = "${pkgs.nodejs}/bin/node";
in

{
  generateDirectory = pkgs.writeScriptBin "generate-directory" ''
    if [ $# -eq 0 ]
      then
        echo "Usage: generate-directory [EXTENSION]"
      else
        DIRECTORY="./jupyterlab"
        echo "Generating directory '$DIRECTORY' with extensions:"

        # we need to copy yarn.lock manually to the staging directory to get
        # write access this seems to be a bug in jupyterlab that doesn't
        # consider that it comes from a folder without read access only as in
        # Nix
        mkdir -p "$DIRECTORY"/staging
        cp ${jupyter}/lib/python3.7/site-packages/jupyterlab/staging/yarn.lock "$DIRECTORY"/staging
        chmod +w "$DIRECTORY"/staging/yarn.lock

        for EXT in "$@"; do echo "- $EXT"; done
        ${jupyter}/bin/jupyter-labextension install "$@" --app-dir="$DIRECTORY" --generate-config
        chmod -R +w "$DIRECTORY"/*
    fi
  '';

  generateLockFile = pkgs.writeScriptBin "generate-lockfile" ''
    if [ $# -eq 0 ]
      then
        echo "Usage: generate-lockfile [EXTENSION]"
      else
        DIRECTORY=$(mktemp -d)
        WORKDIR="workdir"

        mkdir -p "$DIRECTORY"/staging
        cp ${jupyter}/lib/python3.7/site-packages/jupyterlab/staging/yarn.lock "$DIRECTORY"/staging
        chmod +w "$DIRECTORY"/staging/yarn.lock

        echo "Generating lockfile for extensions:"

        for EXT in "$@"; do echo "- $EXT"; done
        ${jupyter}/bin/jupyter-labextension install "$@" --app-dir="$DIRECTORY"

        mkdir -p $WORKDIR/src
        mv "$DIRECTORY/staging/yarn.lock" $WORKDIR/src
        mv "$DIRECTORY/staging/package.json" $WORKDIR/src
        mv "$DIRECTORY/extensions" $WORKDIR
    fi
  '';

  mkDirectoryFromLockFile = { path, sha256 }:
    pkgs.stdenv.mkDerivation {
      name = "jupyterlab-from-lockfile";
      phases = [ "installPhase" ];
      nativeBuildInputs = [ pkgs.breakpointHook ];
      buildInputs = [ jupyter pkgs.nodejs pkgs.inotifyTools ];
      installPhase = ''
        export HOME=$TMP

        # Make the yarn.lock file accessible to the builder.
        mkdir -p folder/staging
        cp ${path} folder/staging/yarn.lock
        chmod +rw folder/staging/yarn.lock

        # Build the folder a first time. This will download all dependencies,
        # but the build will fail, because of hard-coded references on
        # executables. We will patch these executables after, that's why we
        # ignore the errors here.
        jupyter lab build --app-dir folder --debug || true

        # Patch executables so they point to the correct node.
        echo "Patching node..."
        BIN_PATH=folder/staging/node_modules/.bin
        for FILE in $(find $BIN_PATH -not -path $BIN_PATH); do
          echo "Patching $FILE."
          substituteInPlace $FILE --replace "/usr/bin/env node" ${nodeBin}
        done

        # Make files in the staging folder accessible.
        chmod -R +rw folder

        # Build once more, with patched executables.
        jupyter lab build --app-dir folder --debug

        # Move the Jupyter folder to the correct location.
        mkdir -p $out
        mv folder/{extensions,schemas,settings,static,themes,imports.css} $out
      '';

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = sha256;
    };

  mkDirectoryWith = { extensions }:
    # Creates a JUPYTERLAB_DIR with the given extensions.
    # This operation is impure
    let extStr = pkgs.lib.concatStringsSep " " extensions; in
    pkgs.stdenv.mkDerivation {
      name = "jupyterlab-extended";
      phases = "installPhase";
      buildInputs = [ jupyter pkgs.nodejs ];
      installPhase = ''
        export HOME=$TMP

        mkdir -p appdir/staging
        cp ${jupyter}/lib/python3.7/site-packages/jupyterlab/staging/yarn.lock appdir/staging
        chmod +w appdir/staging/yarn.lock

        jupyter labextension install ${extStr} --app-dir=appdir --debug
        rm -rf appdir/staging/node_modules
        mkdir -p $out
        cp -r appdir/* $out
      '';
    };
}
