# #
## Copyright (c) 2019 Matthias Tafelmeier
##
## This file is part of godon
##
## godon is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## godon is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Affero General Public License for more details.
##
## You should have received a copy of the GNU Affero General Public License
## along with godon. If not, see <http://www.gnu.org/licenses/>.
##

{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot = {
    loader = { grub.enable = true; };
    ## CVE-2026-98432 (IPv4 TCP, remote, unauthenticated; RHSB-2026-016):
    ## fixed upstream in linux 6.12.113. Assert the floor so a stale or
    ## frozen channel (nixos-24.05 sits at 6.12.7, the old 26.05 snapshot
    ## at 6.12.111) fails the build loudly instead of rebooting into a
    ## vulnerable kernel.
    kernelPackages =
      assert (lib.versionAtLeast pkgs.linuxPackages_6_12.kernel.version "6.12.113");
      pkgs.linuxPackages_6_12;
  };

  services = {
    openssh.enable = true;
    github-runners.gh-runner = {
      enable = true;
      ## stable registration name: the module default (gh-runner). The
      ## orphaned entries (gh-runner, gh-runner2) were removed from the
      ## org UI on 2026-11-01 — same-name re-registration works again,
      ## no more name walking.
      url = "https://github.com/godon-dev";
      tokenFile = "/srv/gh_runner.token";
      extraLabels = [ "nixos" "osuosl" ];
      extraPackages = with pkgs; [ nixos-generators mask kind kubernetes-helm docker docker-compose iproute2 jq yq-go ];
      workDir = "/github-runner/";
      serviceOverrides = {
        PrivateUsers = false;
        DynamicUser = false;
        PrivateDevices = false;
        PrivateMounts = false;
        AmbientCapabilities = [ "CAP_NET_ADMIN" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
      };
    };
  };

  # create github-runner work dir
  systemd.tmpfiles.rules = [ "d /github-runner/ 0755 root root -" "d /github-runner/artifacts 0755 root root -" ];
  # override docker limits
  systemd.services.docker.serviceConfig = { LimitNOFILE=4194304; };

  environment.systemPackages = let
    pythonModules = pythonPackages: with pythonPackages; [ pyyaml ];
  in with pkgs; [
    (python3.withPackages pythonModules)
    ansible
    ## bashInteractive_5 was dropped as an attr name in the nixos-26.05
    ## snapshot; bashInteractive is the same interactive bash 5.x line.
    bashInteractive
    cargo
    clang
    ctags
    curl
    docker
    docker-compose
    ethtool
    git
    git-crypt
    gnupg
    htop
    iperf3
    iproute2
    jq
    yq-go
    killall
    kind
    kubernetes-helm
    mask
    nmap
    nixos-generators
    openssh
    parted
    pciutils
    rsync
    tcpdump
    tcpflow
    traceroute
    tree
    unzip
    util-linux
    wget
    vim
  ];

  users.users.godon = {
    isNormalUser = true;
    home = "/home/godon/";
    extraGroups = [ "wheel" "docker" "libvirtd" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL8M0dSABT396Fj3V0xplrvg/LnIf5mP1xmDPpetSTCo godon@osuosl-runner"
    ];
  };

  users.users.github-runner-nixos = {
    isNormalUser = true;
    home = "/home/github-runner-nixos/";
    extraGroups = [ "wheel" "docker" "libvirtd" "systemd-network" ];
    openssh.authorizedKeys.keys = [
    ];
  };

  virtualisation = {
    docker.enable = true;
    vswitch.enable = true;
    libvirtd = {
      enable = true;
      onShutdown = "shutdown";
    };
  };

  ## Required for kind cluster to work network wise
  networking.firewall.checkReversePath = "loose";

  security = {
    sudo.wheelNeedsPassword = false; # for automatic use
    polkit = { enable = true; };
    pam.loginLimits = [
      {
        domain = "*";
        type = "soft";
        item = "nofile";
        value = "4194304";
      }
      {
        domain = "*";
        type = "hard";
        item = "nofile";
        value = "4194304";
      }
    ];
  };

  nixpkgs.config.allowUnfree = true;
}
