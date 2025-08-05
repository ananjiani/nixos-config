{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Interactive process viewer - shows CPU, memory usage, process trees
    # Better than 'top' with mouse support and color coding
    htop

    # Disk I/O monitor - shows which processes are reading/writing to disk
    # Useful for finding what's causing high disk activity
    iotop

    # NCurses disk usage analyzer - interactive tool to find what's using disk space
    # Navigate directories and see folder/file sizes visually
    ncdu

    # Additional monitoring tools you might want to add later:
    # btop        # Even fancier resource monitor with graphs
    # nethogs     # Network bandwidth by process (like iotop but for network)
    # iftop       # Network connections monitor
    # lnav        # Log file navigator with syntax highlighting
  ];
}
