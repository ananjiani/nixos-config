# Dendritic MoonDeck Module
# This module follows the dendritic pattern - aspect-oriented configuration
# that can span multiple configuration classes (homeManager, nixos, darwin, etc.)
_:

let
  # Native source build of upstream v1.9.2, patched so SteamHandler::launchApp
  # no longer refuses to launch when the Steam UI mode is Unknown (the MoonDeck
  # runner on the Steam Deck is patched to accept Unknown, but stock Buddy
  # rejects it). All other safety checks (current user, app-id, process/log
  # trackers, app-state) are preserved.
  #
  # Additionally, the Linux process handler is patched to read parent PID and
  # start time from /proc/<pid>/stat directly instead of the libproc2 pids API:
  # procps_pids_new/select/unref leaks one /proc/<pid> dirfd per call, and the
  # Steam process tracker calls getStartTime() every second, so Buddy hits
  # LimitNOFILE (1024) after ~17 minutes, falsely declares Steam dead, ends the
  # stream and crashes. libproc2 is kept only for the one-shot boot-time read.
  mkMoondeckBuddy =
    pkgs:
    pkgs.stdenv.mkDerivation {
      pname = "moondeck-buddy";
      version = "1.9.2";

      src = pkgs.fetchFromGitHub {
        owner = "FrogTheFrog";
        repo = "moondeck-buddy";
        rev = "c7cccf9c02cfc610c78daa4afac167f704771f53"; # tag v1.9.2
        fetchSubmodules = true; # resources/ssl certs are a submodule, baked into Qt resources
        hash = "sha256-GhZlmdI+oa5BjEzr9bkR2sY/nVpd1nuJlT2hYYv6zGU=";
      };

      postPatch = ''
                substituteInPlace src/lib/os/steamhandler.cpp \
                  --replace-fail '    if (getSteamUiMode() == enums::SteamUiMode::Unknown)
            {
                qCWarning(lc::os) << "Steam is not running or has not reached a stable state yet!";
                return false;
            }
        ' ""

        substituteInPlace src/lib/os/linux/nativeprocesshandler.cpp \
          --replace-fail '#include <libproc2/pids.h>
        #include <libproc2/stat.h>
        #include <sys/types.h>' '#include <QFile>
        #include <cmath>
        #include <libproc2/stat.h>
        #include <sys/types.h>
        #include <unistd.h>'

        old="$(cat <<'MOONDECK_OLD_EOF'
        template<class ItemValue, class Getter>
        ItemValue getPidItem(const uint pid, const pids_item item, const ItemValue& fallback, Getter&& getter)
        {
            std::array items{item};

            pids_info* info{nullptr};
            if (const int error = procps_pids_new(&info, items.data(), items.size()); error < 0)
            {
                qWarning(lc::os) << "Failed at procps_pids_new for" << pid << "-" << lc::getErrorString(error * -1);
                return fallback;
            }

            const auto cleanup{qScopeGuard([&]() { procps_pids_unref(&info); })};

            std::array  pids{pid};
            const auto* result{procps_pids_select(info, pids.data(), pids.size(), PIDS_SELECT_PID)};

            if (!result)
            {
                qWarning(lc::os) << "Failed at procps_pids_select for" << pid << "-" << lc::getErrorString(errno);
                return fallback;
            }

            if (!result->counts || result->counts->total <= 0)
            {
                return fallback;
            }

            const auto* head_ptr{result->stacks && result->stacks[0]->head ? result->stacks[0]->head : nullptr};
            if (!head_ptr)
            {
                qWarning(lc::os) << "Failed at procps_pids_select for" << pid << "-" << lc::getErrorString(errno);
                return fallback;
            }

            return std::forward<Getter>(getter)(head_ptr->result);
        }

        uint getParentPid(const uint pid)
        {
            return getPidItem(pid, PIDS_ID_PPID, 0u,
                              [](const auto& result) { return result.s_int >= 0 ? static_cast<uint>(result.s_int) : 0u; });
        }

        QDateTime getStartTime(const uint pid)
        {
            return getPidItem(pid, PIDS_TIME_START, QDateTime{},
                              [](const auto& result)
                              {
                                  const auto boot_time{getBootTime()};
                                  if (!boot_time)
                                  {
                                      return QDateTime{};
                                  }

                                  const auto milliseconds{static_cast<int>(std::round((result.real) * 1000.0))};
                                  const auto datetime{QDateTime::fromSecsSinceEpoch(*boot_time)};
                                  return datetime.addMSecs(milliseconds);
                              });
        }
        MOONDECK_OLD_EOF
        )"

        new="$(cat <<'MOONDECK_NEW_EOF'
        // Reads the fields of /proc/<pid>/stat that follow the comm field (i.e.
        // starting with field 3, "state"). The comm field can contain spaces and
        // parentheses, so everything up to the final closing parenthesis is skipped.
        std::optional<QList<QByteArray>> getStatFields(const uint pid)
        {
            QFile file{"/proc/" + QString::number(pid) + "/stat"};
            if (!file.open(QIODevice::ReadOnly))
            {
                // Process is likely gone already; matches the silent fallback of the
                // previous libproc2-based lookup.
                return std::nullopt;
            }

            const QByteArray contents{file.readAll()};
            const auto       comm_end{contents.lastIndexOf(')')};
            if (comm_end < 0)
            {
                qWarning(lc::os) << "Malformed /proc/<pid>/stat contents for" << pid;
                return std::nullopt;
            }

            return contents.mid(comm_end + 1).simplified().split(' ');
        }

        uint getParentPid(const uint pid)
        {
            // Field 4 (ppid) is the 2nd field after the comm field.
            const auto fields{getStatFields(pid)};
            if (!fields || fields->size() < 2)
            {
                return 0u;
            }

            bool       converted{false};
            const uint parent_pid{fields->at(1).toUInt(&converted)};
            return converted ? parent_pid : 0u;
        }

        QDateTime getStartTime(const uint pid)
        {
            // Field 22 (starttime) is the 20th field after the comm field, in clock
            // ticks since boot.
            const auto fields{getStatFields(pid)};
            if (!fields || fields->size() < 20)
            {
                return QDateTime{};
            }

            bool             converted{false};
            const qulonglong start_ticks{fields->at(19).toULongLong(&converted)};
            if (!converted)
            {
                return QDateTime{};
            }

            const auto boot_time{getBootTime()};
            if (!boot_time)
            {
                return QDateTime{};
            }

            const long ticks_per_sec{sysconf(_SC_CLK_TCK)};
            if (ticks_per_sec <= 0)
            {
                return QDateTime{};
            }

            const auto milliseconds{static_cast<qint64>(
                std::round(static_cast<double>(start_ticks) / static_cast<double>(ticks_per_sec) * 1000.0))};
            return QDateTime::fromSecsSinceEpoch(*boot_time).addMSecs(milliseconds);
        }
        MOONDECK_NEW_EOF
        )"

        substituteInPlace src/lib/os/linux/nativeprocesshandler.cpp \
          --replace-fail "$old" "$new"
      '';

      nativeBuildInputs = [
        pkgs.cmake
        pkgs.qt6.wrapQtAppsHook
      ];

      buildInputs = [
        pkgs.qt6.qtbase # Core, Widgets, Network, DBus
        pkgs.qt6.qthttpserver
        pkgs.qt6.qtwayland # runtime platform plugin
        pkgs.procps # libproc2, used by the Linux process tracker
      ];

      # Reproduce the AppImage AppRun interface: `moondeck-buddy` runs
      # MoonDeckBuddy, `moondeck-buddy --exec MoonDeckStream` runs the stream
      # binary. Created in postFixup so wrapQtAppsHook doesn't double-wrap it.
      postFixup = ''
        cat > $out/bin/moondeck-buddy <<EOF
        #!${pkgs.runtimeShell}
        if [ "\$1" = "--exec" ]; then
          binary="\$2"
          shift 2
          exec "$out/bin/\$binary" "\$@"
        fi
        exec "$out/bin/MoonDeckBuddy" "\$@"
        EOF
        chmod +x $out/bin/moondeck-buddy
      '';

      meta = {
        description = "Server-side buddy app to control the PC and Steam from a Steam Deck via the MoonDeck plugin";
        homepage = "https://github.com/FrogTheFrog/moondeck-buddy";
        license = pkgs.lib.licenses.lgpl3Only;
        mainProgram = "moondeck-buddy";
      };
    };
in
{
  # NixOS configuration (system-level package and Sunshine integration)
  flake.aspects.moondeck.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.moondeck = {
        enable = lib.mkEnableOption "MoonDeck Buddy system-level package";

        sunshine = {
          enable = lib.mkEnableOption "Configure MoonDeckStream in Sunshine apps";

          appName = lib.mkOption {
            type = lib.types.str;
            default = "MoonDeckStream";
            description = "Application name shown in Moonlight";
          };
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open firewall port for MoonDeck Buddy (59999)";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 59999;
          description = "Port for MoonDeck Buddy";
        };
      };

      config = lib.mkIf config.moondeck.enable {
        # Install package system-wide
        environment.systemPackages = [ (mkMoondeckBuddy pkgs) ];

        # Open firewall for MoonDeck Buddy
        networking.firewall.allowedTCPPorts = lib.mkIf config.moondeck.openFirewall [
          config.moondeck.port
        ];

        # Configure Sunshine to include MoonDeckStream
        services.sunshine.applications = lib.mkIf config.moondeck.sunshine.enable {
          apps = [
            {
              name = config.moondeck.sunshine.appName;
              cmd = "${lib.getExe' pkgs.util-linux "setpriv"} --inh-caps=-all --ambient-caps=-all -- ${mkMoondeckBuddy pkgs}/bin/moondeck-buddy --exec MoonDeckStream";
            }
          ];
        };
      };
    };

  # Home Manager configuration (user-level service and settings)
  flake.aspects.moondeck.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.moondeck = {
        enable = lib.mkEnableOption "MoonDeck Buddy for Steam Deck game streaming";

        autostart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Auto-start MoonDeck Buddy via systemd user service";
        };

        settings = lib.mkOption {
          type = lib.types.submodule {
            freeformType = lib.types.attrsOf lib.types.anything;
            options = {
              port = lib.mkOption {
                type = lib.types.port;
                default = 59999;
                description = "Communication port for MoonDeck Buddy";
              };

              loggingrules = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Logging rules (e.g., 'buddy.*.debug=true' for debug logging)";
              };

              preferhibernation = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Use hibernation instead of suspend";
              };

              closesteambeforesleep = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Automatically close Steam before sleep/hibernation";
              };

              sslprotocol = lib.mkOption {
                type = lib.types.str;
                default = "SecureProtocols";
                description = "SSL/TLS protocol version (SecureProtocols, TlsV1_2, TlsV1_3, etc.)";
              };

              macaddressoverride = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Manual MAC address override";
              };

              steamexecoverride = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Custom Steam executable path";
              };

              sunshineappsfilepath = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Path to Sunshine's apps.json file";
              };
            };
          };
          default = { };
          description = "MoonDeck Buddy settings (written to ~/.config/moondeckbuddy/settings.json)";
        };
      };

      config = lib.mkIf config.moondeck.enable {
        # Note: Package is installed system-wide via NixOS aspect
        # settings.json is managed by the app itself at ~/.config/moondeckbuddy/settings.json
        # The app needs write access to update settings, so we don't use declarative config here

        # Systemd user service (runs in graphical session)
        systemd.user.services.moondeckbuddy = lib.mkIf config.moondeck.autostart {
          Unit = {
            Description = "MoonDeck Buddy";
            Documentation = "https://github.com/FrogTheFrog/moondeck-buddy/wiki";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };

          Service = {
            Type = "simple";
            ExecStart = "${mkMoondeckBuddy pkgs}/bin/moondeck-buddy";
            Restart = "on-failure";
            RestartSec = "5s";
          };

          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
    };
}
