# Minimal, hardened NixOS dev box for Raspberry Pi (aarch64).
# - SSH reachable only over Tailscale
# - "admin" can sudo / change the system; "agent" (group "dev") can only run code
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- Basics ----------------------------------------------------------------
  system.stateVersion = "25.11"; # keep at the release you first installed
  networking.hostName = "devbox";
  time.timeZone = "UTC";

  # Raspberry Pi: no UEFI, boot via extlinux
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  hardware.enableRedistributableFirmware = true; # Pi wifi/bluetooth/firmware blobs
  zramSwap.enable = true; # compressed swap in RAM; helps on low-memory Pis

  # --- Minimalism ------------------------------------------------------------
  environment.defaultPackages = [ ];
  documentation.enable = false;
  programs.command-not-found.enable = false;
  environment.systemPackages = with pkgs; [ curl tmux vim git-credential-manager ];
  programs.nix-ld.enable = true; # lets downloaded generic Linux binaries run
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      credential.helper = "manager";
      credential.credentialStore = "secretservice";
    };
    push.autoSetupRemote = true;
  };
  services.gnome.gnome-keyring.enable = true;
  # --- Users -----------------------------------------------------------------
  users.mutableUsers = false;
  users.users.root.hashedPassword = "!"; # root login disabled

  # Admin: the only account that can escalate / rebuild the system.
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "REPLACE_ME"; # generate with: mkpasswd -m yescrypt
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... admin" ];
  };

  # Agent: runs code and programs, no sudo, cannot touch the NixOS config.
  users.groups.dev = { };
  users.users.agent = {
    isNormalUser = true;
    uid = 1001; # pinned so the resource limits below match
    group = "dev";
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... agent" ];
  };

  security.sudo.execWheelOnly = true; # sudo binary unusable by non-wheel
  security.sudo.wheelNeedsPassword = true;

  # --- Nix -------------------------------------------------------------------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    allowed-users = [ "@wheel" "@dev" ]; # dev can use nix (sandboxed builds)...
    trusted-users = [ "root" ]; # ...but is never trusted
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  # --- Tailscale + firewall --------------------------------------------------
  # First boot: `sudo tailscale up` (or set services.tailscale.authKeyFile).
  services.tailscale = {
    enable = true;
    openFirewall = true; # opens only the WireGuard UDP port for direct links
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ]; # nothing open on public interfaces
    interfaces.tailscale0.allowedTCPPorts = [ 22 ]; # SSH only via tailnet
  };

  # --- SSH -------------------------------------------------------------------
  services.openssh = {
    enable = true;
    openFirewall = false; # firewall rule above handles it
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "admin" "agent" ];
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding = "local"; # allow `ssh -L`; set "no" to forbid
      MaxAuthTries = 3;
      LoginGraceTime = 20;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };
  };

  # --- Kernel / system hardening ---------------------------------------------
  security.protectKernelImage = true;

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
  };

  # --- Keep runaway agents from starving sshd/tailscale ----------------------
  environment.etc."systemd/system/user-1001.slice.d/limits.conf".text = ''
    [Slice]
    MemoryHigh=70%
    MemoryMax=80%
    TasksMax=4096
  '';
}
