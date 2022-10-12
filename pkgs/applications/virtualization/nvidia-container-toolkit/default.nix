{ lib
, fetchFromGitHub
, buildGoModule
, makeWrapper
, linkFarm
, writeShellScript
, containerRuntimePath
, configTemplate
, glibc
, cudaPackages
}:
let
  isolatedContainerRuntimePath = linkFarm "isolated_container_runtime_path" [
    {
      name = "runc";
      path = containerRuntimePath;
    }
  ];
  warnIfXdgConfigHomeIsSet = writeShellScript "warn_if_xdg_config_home_is_set" ''
    set -eo pipefail

    if [ -n "$XDG_CONFIG_HOME" ]; then
      echo >&2 "$(tput setaf 3)warning: \$XDG_CONFIG_HOME=$XDG_CONFIG_HOME$(tput sgr 0)"
    fi
  '';
in
buildGoModule rec {
  pname = "nvidia-container-toolkit";
  version = "1.11.0";

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-rI/J14eNxOSqgQqlJpqwgNT2AOYXhxg1aAfgh/XKy3w=";
  };

  vendorSha256 = null;
  # proxyVendor = true;
  ldflags = [ "-s" "-w" ];
  nativeBuildInputs = [ makeWrapper cudaPackages.cudatoolkit ];

  # undefined symbol cuDriverGetVersion
  doCheck = false;

  postInstall = ''
    # nvidia-container-runtime postInstall script
    mkdir -p $out/etc/nvidia-container-runtime

    # nvidia-container-runtime invokes docker-runc or runc if that isn't
    # available on PATH.
    #
    # Also set XDG_CONFIG_HOME if it isn't already to allow overriding
    # configuration. This in turn allows users to have the nvidia container
    # runtime enabled for any number of higher level runtimes like docker and
    # podman, i.e., there's no need to have mutually exclusivity on what high
    # level runtime can enable the nvidia runtime because each high level
    # runtime has its own config.toml file.
    wrapProgram $out/bin/nvidia-container-runtime \
      --run "${warnIfXdgConfigHomeIsSet}" \
      --prefix PATH : ${isolatedContainerRuntimePath} \
      --set-default XDG_CONFIG_HOME $out/etc

    cp ${configTemplate} $out/etc/nvidia-container-runtime/config.toml

    substituteInPlace $out/etc/nvidia-container-runtime/config.toml \
      --subst-var-by glibcbin ${lib.getBin glibc}

    # nvidia-container-toolkit postInstall
    #ls $out/bin
    #mv $out/bin/{pkg,${pname}}
    #ln -s $out/bin/nvidia-container-{toolkit,runtime-hook}

    wrapProgram $out/bin/nvidia-ctk \
      --add-flags "-config $out/etc/nvidia-container-runtime/config.toml"
  '';

  meta = with lib; {
    homepage = "https://github.com/NVIDIA/nvidia-container-toolkit";
    description = "NVIDIA container runtime hook";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = with maintainers; [ cpcloud ];
  };
}
