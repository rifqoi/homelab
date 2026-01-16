{...}: {
  imports = [
    ../../modules/monitoring/node-exporter.nix
  ];

  features.monitoring.nodeExporter = {
    enable = true;
    enabledCollectors = [];
  };
}
