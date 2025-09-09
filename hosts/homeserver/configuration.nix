# Homeserver configuration
{
  inputs,
  pkgs-stable,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./storage.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../modules/nixos/utils.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/nvidia.nix # NVIDIA GPU support for WhisperX
  ];

  # Set hostname
  networking.hostName = "homeserver";

  # Enable CUDA support for packages (needed for WhisperX with GPU acceleration)
  nixpkgs.config.cudaSupport = true;

  # No overlays needed - using faster-whisper with CTranslate2 instead

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Enable Docker as fallback for any services that might need it
  virtualisation.docker.enable = true;

  # System packages (with CUDA support enabled)
  environment.systemPackages = with pkgs-stable; [ whisperx ];
  # environment.systemPackages =
  #   with pkgs;
  #   let
  #     # Python environment with transcription tools
  #     transcribePython = python3.withPackages (
  #       ps: with ps; [
  #         faster-whisper
  #         pyannote-audio
  #         pydub
  #         numpy
  #         scipy
  #         tqdm
  #       ]
  #     );

  #     # Transcription wrapper script
  #     transcribeScript = writeScriptBin "transcribe" ''
  #       #!${transcribePython}/bin/python3
  #       ${builtins.readFile ./transcribe.py}
  #     '';
  #   in
  #   [
  #     # Audio processing tools
  #     ffmpeg

  #     # Transcription script with all dependencies
  #     transcribeScript
  #   ];

  # Services configuration
  services = {
    # SSH is now configured via the ssh.nix module

    # Nginx reverse proxy with Let's Encrypt
    nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;

      # Fix proxy headers hash warning
      appendHttpConfig = ''
        proxy_headers_hash_max_size 512;
        proxy_headers_hash_bucket_size 128;
      '';

      virtualHosts."git.dimensiondoor.xyz" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
          proxyWebsockets = true;
          extraConfig = ''
            # Connection header is handled by proxyWebsockets
            # Other headers are included via recommendedProxySettings

            # Increase client body size for Git LFS
            client_max_body_size 500M;
          '';
        };
      };

      virtualHosts."media.dimensiondoor.xyz" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8096";
          proxyWebsockets = true;
          extraConfig = ''
            # Jellyfin specific headers
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            # Disable buffering when the nginx proxy gets very resource heavy upon streaming
            proxy_buffering off;
          '';
        };
      };
    };

    forgejo = {
      enable = true;
      lfs.enable = true;

      # Minimal configuration for testing
      database = {
        type = "sqlite3";
        createDatabase = true;
      };

      settings = {
        server = {
          DOMAIN = "git.dimensiondoor.xyz";
          ROOT_URL = "https://git.dimensiondoor.xyz/";
          HTTP_ADDR = "0.0.0.0";
          HTTP_PORT = 3000;
          # Increase LFS file size limit to 500MB
          LFS_MAX_FILE_SIZE = 524288000;
        };

        service = {
          DISABLE_REGISTRATION = true;
        };

        security = {
          INSTALL_LOCK = true;
        };
      };
    };

    # homeserver-forgejo = {
    #   enable = true;
    #   domain = "localhost"; # Local access only
    # };

    # homeserver-home-assistant = {
    #   enable = true;
    #   domain = "homeassistant.local"; # Local access only
    #   # Voice assistant, ESPHome, Matter, and Signal CLI are enabled by default
    # };
  };

  nixarr = {
    enable = true;
    mediaDir = "/mnt/storage/arr-data/media";
    stateDir = "/data/.state/nixarr"; # Fresh state directory

    # VPN configuration for Transmission
    # vpn = {
    #   enable = true;
    #   wgConf = "/mnt/storage/arr-data/torrents/wireguard/wg0.conf"; # Your existing path
    #   accessibleFrom = [
    #     "10.27.27.0/24" # Allow access from your local network
    #     "192.168.1.0/24" # Default ranges
    #     "192.168.0.0/24"
    #     "127.0.0.1"
    #   ];
    # };

    jellyfin = {
      enable = true;
      openFirewall = true;
    };

    prowlarr = {
      enable = true;
      openFirewall = true;
    };

    radarr = {
      enable = true;
      openFirewall = true;
    };

    sonarr = {
      enable = true;
      openFirewall = true;
    };

    transmission = {
      enable = true;
      # vpn.enable = true;
      openFirewall = true;
      peerPort = 51413;

      # Allow access from local network
      extraAllowedIps = [
        "10.27.27.0/24" # Your local network subnet
      ];

      # Private tracker optimizations and cross-seed
      privateTrackers = {
        disableDhtPex = true; # Disable DHT/PEX for private trackers
        cross-seed = {
          enable = true;
          indexIds = [ ]; # Will be populated with your Prowlarr indexer IDs after setup
          extraSettings = {
            delay = 20; # Wait 20 seconds before cross-seeding
            port = 2468; # Cross-seed web UI port (http://10.27.27.11:2468)
          };
        };
      };

      extraSettings = {
        # Use your existing download directories
        download-dir = "/mnt/storage/arr-data/torrents/downloads"; # Your existing complete dir
        incomplete-dir = "/mnt/storage/arr-data/torrents/temp"; # Your existing incomplete dir
        incomplete-dir-enabled = true;
        watch-dir-enabled = false;

        # Seed settings for private tracker ratio
        ratio-limit = 2;
        ratio-limit-enabled = true;
        idle-seeding-limit = 10080;
        idle-seeding-limit-enabled = true;

        # Performance settings
        download-queue-size = 10;
        peer-limit-global = 500;
        peer-limit-per-torrent = 100;
      };
    };

    # Autobrr for racing and ratio building
    autobrr = {
      enable = true;
      openFirewall = true;

      settings = {
        checkForUpdates = false;
        host = "0.0.0.0";
        port = 7474;
        logLevel = "INFO";
      };
    };

    # Recyclarr for automatic quality configuration
    recyclarr = {
      enable = true;
      schedule = "daily"; # Updates daily with latest TRaSH guides

      configuration = {
        sonarr = {
          "sonarr" = {
            base_url = "http://localhost:8989";
            api_key = "!secret sonarr"; # Will be auto-generated

            quality_definition = {
              type = "series";
            };

            custom_formats = [
              {
                trash_ids = [
                  # Unwanted formats
                  "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
                  "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
                  "90cedc1fea7ea5d11298bebd3d1d3223" # EVO except WEB-DL
                  "b17886cb4158d9fea189859409975758" # HDR10+ Boost
                ];
                quality_profiles = [
                  { name = "HD-1080p"; }
                  { name = "Ultra-HD"; }
                ];
              }
            ];

            release_profiles = [
              {
                trash_ids = [
                  "76e060895c5b8a765c310933da0a5357" # Optionals
                ];
                filter = {
                  include = [
                    { name = "HD-1080p"; }
                    { name = "Ultra-HD"; }
                  ];
                };
              }
            ];
          };
        };

        radarr = {
          "radarr" = {
            base_url = "http://localhost:7878";
            api_key = "!secret radarr"; # Will be auto-generated

            quality_definition = {
              type = "movie";
            };

            custom_formats = [
              {
                trash_ids = [
                  # Audio formats
                  "496f355514737f7d83bf7aa4d24f8169" # TrueHD Atmos
                  "2f22d89048b01681dde8afe203bf2e95" # DTS X
                  "417804f7f2c4308c1f4c5d380d4c4475" # ATMOS (undefined)
                  "1af239278386be2919e1bcee0bde047e" # DD+ Atmos

                  # HDR formats
                  "e23edd2482476e595fb990b12e7c609c" # DV HDR10
                  "58d6a88f13e2db7f5059c41047876f00" # DV
                  "55d53828b9d81cbe20b02efd00aa0efd" # DV HLG
                  "a3e19f8f627608af0211acd02bf89735" # DV SDR
                  "e61e28db95d22bedcadf030b8f156d96" # HDR
                  "2a4d9069cc1fe3242ff9bdaebed239bb" # HDR (undefined)
                  "dfb86d5941bc9075d6af23b09c2aeecd" # HDR10
                  "b974a6cd08c1066250f1f177d7aa1225" # HDR10+
                  "9364dd386c9b4a1100dde8264690add7" # HLG
                ];
                quality_profiles = [
                  {
                    name = "Ultra-HD";
                    score = 100;
                  }
                ];
              }
              {
                trash_ids = [
                  # Unwanted
                  "ed38b889b31be83fda192888e2286d83" # BR-DISK
                  "90a6f9a284dff5103f6346090e6280c8" # LQ
                  "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
                ];
                quality_profiles = [
                  {
                    name = "HD-1080p";
                    score = -10000;
                  }
                  {
                    name = "Ultra-HD";
                    score = -10000;
                  }
                ];
              }
            ];
          };
        };
      };
    };
  };

  # ACME/Let's Encrypt configuration
  security.acme = {
    acceptTerms = true;
    defaults.email = "ammar.nanjiani@gmail.com";
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    # These will be managed by individual services
    allowedTCPPorts = [
      22 # SSH
      80 # HTTP (for ACME challenge)
      443 # HTTPS
      3000 # Forgejo HTTP (local only)
    ];
  };

  # User configuration for VM testing
  users.users.root.initialPassword = "test";
  # SSH keys are now managed via the ssh.nix module
  users.users.ammar = { };

  # Allow wheel group to use sudo without password (optional)
  security.sudo.wheelNeedsPassword = false;

  # Enable automatic updates
  # system.autoUpgrade = {
  #   enable = true;
  #   allowReboot = false; # Manual reboots for servers
  # };

}
