// ═══════════════════════════════════════════════════════════════
// Grafana Alloy — Per-Cluster Telemetry Collector
// ═══════════════════════════════════════════════════════════════
//
// Collects metrics, logs, and traces from this cluster and sends
// them to local Mimir, Loki, and Tempo backends (all in-cluster).
// All writes stay intra-cluster — no cross-cluster egress for
// telemetry ingestion. Only object storage API calls leave the
// cluster (free ingress on S3/GCS).
//
// Signals:
//   Metrics  → Prometheus scraping + ServiceMonitors → Mimir
//   Logs    → Kubernetes pod logs (via K8s API)     → Loki
//   Traces  → OTLP receiver + k8sattributes          → Tempo
//
// Istio ambient mesh metrics (istiod, ztunnel, waypoints) are
// scraped directly, replacing the separate OTel Collector.
// Once verified, the otel-istio-scraper can be decommissioned.
//
// NOTE: The Kiali CR currently uses X-Scope-OrgID: istio-${clusterName}
// to query Mimir. Alloy writes all metrics to tenant ${clusterName}.
// Update the Kiali CR's custom_headers.X-Scope-OrgID to ${clusterName}
// (drop the "istio-" prefix) so Kiali can see all cluster metrics,
// not just the ones from the old OTel Collector.

// ─── Cluster Identity ───────────────────────────────────────
// Passed via alloy.extraEnv from Flux ${clusterName} substitution.
local.cluster_name = env("CLUSTER_NAME")

// ═══════════════════════════════════════════════════════════════
// METRICS
// ═══════════════════════════════════════════════════════════════

// Central hub: adds the `cluster` external label to every metric
// before remote write. This label is essential for multi-cluster
// querying in Grafana (filter by cluster=...).
prometheus.relabel "add_cluster" {
  forward_to = [prometheus.remote_write.mimir.receiver]

  rule {
    target_label = "cluster"
    replacement  = local.cluster_name
    action       = "replace"
  }
}

// Remote write to local Mimir (in-cluster, no egress cost).
prometheus.remote_write "mimir" {
  endpoint {
    url = "http://mimir-mimir-gateway.mimir.svc.cluster.local:80/api/v1/push"
    headers = {
      "X-Scope-OrgID" = local.cluster_name,
    }
  }

  // Remote Write v2 reduces network egress by ~50%.
  // Requires --stability.level=experimental on the Alloy binary.
  // To enable, uncomment the line below and add the CLI flag
  // via alloy.extraArgs:
  //   extraArgs:
  //     stability.level: experimental
  // protobuf_message = "io.prometheus.write.v2.Request"
}

// ─── ServiceMonitor & PodMonitor Discovery ───────────────────
// These components watch for ServiceMonitor and PodMonitor CRDs
// across all namespaces and distribute scrape targets across
// Alloy replicas via clustering.

prometheus.operator.servicemonitors "default" {
  forward_to = [prometheus.relabel.add_cluster.receiver]
  clustering {
    enabled = true
  }
}

prometheus.operator.podmonitors "default" {
  forward_to = [prometheus.relabel.add_cluster.receiver]
  clustering {
    enabled = true
  }
}

// ─── Istio Ambient Mesh Metrics ──────────────────────────────
// Replaces the separate OTel Collector (otel-istio-scraper).
// Once Alloy is verified, the OTel Collector can be decommissioned.
//
// Metrics scraped:
//   - istiod:    control plane (pilot_*, istio_build)
//   - ztunnel:   L4 ambient proxy (istio_tcp_*, connection_*)
//   - waypoint:  L7 Envoy proxies (istio_requests_*, envoy_*)
//
// Metric relabel rules match the existing OTel Collector config
// to ensure Kiali compatibility.

// ── Istiod ───────────────────────────────────────────────────
discovery.kubernetes "istiod" {
  role = "endpoints"
  namespaces {
    names = ["istio-system"]
  }
}

discovery.relabel "istiod" {
  targets = discovery.kubernetes.istiod.targets

  rule {
    source_labels = ["__meta_kubernetes_service_name", "__meta_kubernetes_endpoint_port_name"]
    action        = "keep"
    regex         = "istiod;http-monitoring"
  }
}

prometheus.scrape "istiod" {
  targets         = discovery.relabel.istiod.output
  forward_to      = [prometheus.relabel.istiod_metrics.receiver]
  scrape_interval = "15s"

  clustering {
    enabled = true
  }
}

prometheus.relabel "istiod_metrics" {
  forward_to = [prometheus.relabel.add_cluster.receiver]

  rule {
    source_labels = ["__name__"]
    action        = "keep"
    regex         = "istio_build|pilot_info|pilot_proxy_convergence_time_sum|pilot_proxy_convergence_time_count|pilot_services|pilot_xds|pilot_xds_pushes|workload_manager_active_proxy_count|container_cpu_usage_seconds_total|container_memory_working_set_bytes|process_cpu_seconds_total|process_resident_memory_bytes"
  }
}

// ── ztunnel (ambient L4 proxy) ───────────────────────────────
discovery.kubernetes "ztunnel" {
  role = "pod"
  namespaces {
    names = ["istio-system"]
  }
}

discovery.relabel "ztunnel" {
  targets = discovery.kubernetes.ztunnel.targets

  rule {
    source_labels = ["__meta_kubernetes_pod_label_app"]
    action        = "keep"
    regex         = "ztunnel"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_ip"]
    target_label  = "__address__"
    replacement   = "$$1:15020"
  }
}

prometheus.scrape "ztunnel" {
  targets         = discovery.relabel.ztunnel.output
  forward_to      = [prometheus.relabel.ztunnel_metrics.receiver]
  scrape_interval = "15s"
  metrics_path     = "/metrics"

  clustering {
    enabled = true
  }
}

prometheus.relabel "ztunnel_metrics" {
  forward_to = [prometheus.relabel.add_cluster.receiver]

  rule {
    source_labels = ["__name__"]
    action        = "keep"
    regex         = "istio_tcp_connections_closed_total|istio_tcp_connections_opened_total|istio_tcp_received_bytes_total|istio_tcp_sent_bytes_total|istio_requests_total|istio_build|connection_opened|connection_closed"
  }
}

// ── Waypoint proxies (ambient L7) ────────────────────────────
discovery.kubernetes "waypoints" {
  role = "pod"
}

discovery.relabel "waypoints" {
  targets = discovery.kubernetes.waypoints.targets

  rule {
    source_labels = ["__meta_kubernetes_pod_label_istio_io_gateway_name"]
    action        = "keep"
    regex         = ".+"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_ip"]
    target_label  = "__address__"
    replacement   = "$$1:15090"
  }
}

prometheus.scrape "waypoints" {
  targets         = discovery.relabel.waypoints.output
  forward_to      = [prometheus.relabel.waypoint_metrics.receiver]
  scrape_interval = "15s"
  metrics_path     = "/stats/prometheus"

  clustering {
    enabled = true
  }
}

prometheus.relabel "waypoint_metrics" {
  forward_to = [prometheus.relabel.add_cluster.receiver]

  rule {
    source_labels = ["__name__"]
    action        = "keep"
    regex         = "istio_requests_total|istio_request_duration_milliseconds_bucket|istio_request_duration_milliseconds_count|istio_request_duration_milliseconds_sum|istio_request_bytes_bucket|istio_request_bytes_count|istio_request_bytes_sum|istio_response_bytes_bucket|istio_response_bytes_count|istio_response_bytes_sum|istio_request_messages_total|istio_response_messages_total|istio_tcp_connections_closed_total|istio_tcp_connections_opened_total|istio_tcp_received_bytes_total|istio_tcp_sent_bytes_total|envoy_cluster_upstream_cx_active|envoy_cluster_upstream_rq_total|envoy_listener_downstream_cx_active|envoy_listener_http_downstream_rq|envoy_server_memory_allocated|envoy_server_memory_heap_size|envoy_server_uptime"
  }
}

// ═══════════════════════════════════════════════════════════════
// LOGS
// ═══════════════════════════════════════════════════════════════
// Requires Loki to be deployed in the cluster.
// Until Loki is deployed, Alloy will log connection errors for
// loki.write but the metrics and traces pipelines continue working.
// Data is buffered in the WAL and retried automatically.

discovery.kubernetes "pod_logs" {
  role = "pod"
}

loki.source.kubernetes "pod_logs" {
  targets    = discovery.kubernetes.pod_logs.targets
  forward_to = [loki.process.add_cluster.receiver]

  clustering {
    enabled = true
  }
}

// Add the `cluster` label to all log entries for multi-cluster
// querying in Grafana (same as the metrics pipeline).
loki.process "add_cluster" {
  forward_to = [loki.write.loki.receiver]

  stage.static_labels {
    values = {
      cluster = local.cluster_name,
    }
  }
}

loki.write "loki" {
  endpoint {
    url = "http://loki-gateway.loki.svc.cluster.local:80/loki/api/v1/push"
    headers = {
      "X-Scope-OrgID" = local.cluster_name,
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// TRACES
// ═══════════════════════════════════════════════════════════════
// Requires Tempo to be deployed in the cluster.
// Until Tempo is deployed, Alloy will log connection errors for
// otelcol.exporter.otlphttp but the metrics and logs pipelines
// continue working. Data is buffered and retried automatically.
//
// NOTE: If Alloy runs behind Istio ambient mesh (ztunnel), the
// k8sattributes processor may see the ztunnel pod IP instead of
// the application pod IP. If this happens, either:
//   1. Set passthrough = true (only adds k8s.pod.ip, no lookup)
//   2. Configure application SDKs to set k8s.pod.ip resource attr
//   3. Use pod_association rules with known resource attributes

otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  http {
    endpoint = "0.0.0.0:4318"
  }

  output {
    traces = [otelcol.processor.k8sattributes.default.input]
  }
}

otelcol.processor.k8sattributes "default" {
  extract {
    metadata = [
      "k8s.namespace.name",
      "k8s.deployment.name",
      "k8s.statefulset.name",
      "k8s.daemonset.name",
      "k8s.node.name",
      "k8s.pod.name",
      "k8s.pod.uid",
      "k8s.pod.start_time",
    ]
    otel_annotations = true
  }

  output {
    traces = [otelcol.processor.batch.default.input]
  }
}

otelcol.processor.batch "default" {
  output {
    traces = [otelcol.exporter.otlphttp.tempo.input]
  }
}

otelcol.exporter.otlphttp "tempo" {
  client {
    endpoint = "http://tempo.tempo.svc.cluster.local:4318"
    headers = {
      "X-Scope-OrgID" = local.cluster_name,
    }
  }
}
