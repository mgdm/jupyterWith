let
  jupyterLibPath = ../../..;
  jupyter = import jupyterLibPath {};

  iPythonWithPackages = jupyter.kernels.iPythonWith {
    name = "local-package";
    packages = p:
      let
        myPythonPackage = p.buildPythonPackage {
          pname = "my-python-package";
          version = "0.1.0";
          src = ./my-python-package;
        };
      in
        [ myPythonPackage ];
  };

  jupyterlabWithKernels = jupyter.jupyterlabWith {
    kernels = [ iPythonWithPackages ];
    extraPackages = p: [p.hello];
    directory = jupyter.mkDirectoryFromLockFile {
      path = ./yarn.lock;
      sha256 = "1j92qghzizl0fh03f9wxw1gcdas0zcihwi6xb28s0yckbbsy135p";
    };
  };
in
  jupyterlabWithKernels.env
