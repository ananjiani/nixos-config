{
  servers = [
    "192.168.1.53" # HA VIP (keepalived failover between theoden/boromir/samwise)
    "192.168.1.1" # Router fallback
    "9.9.9.9" # Quad9 public fallback
  ];
}
