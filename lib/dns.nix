{
  servers = [
    "192.168.1.53" # HA VIP (keepalived failover between theoden/boromir/samwise)
    "192.168.1.1" # Router fallback
  ];
}
