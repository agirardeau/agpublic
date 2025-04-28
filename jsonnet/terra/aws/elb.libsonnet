// Templates for Elastic Load Balancing resources
local aws = import 'common/aws/aws.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  LoadBalancer: aws.RegionResource + {
    local this = self,

    type: 'aws_lb',
    tag: 'lb',
    load_balancer_type: this.LoadBalancerType.APPLICATION,
    subnets: [],
    security_groups: [],
    internal: false,
    idle_timeout_sec: 60,
    enable_http2: true,
    desync_mitigation_mode: 'defensive',
    
    depends_on: this.subnets + this.security_groups,
    args+: {
      name: this.tag,
      load_balancer_type: this.load_balancer_type,
      subnets: [x.id() for x in this.subnets],
      security_groups: [x.id() for x in this.security_groups],
      internal: this.internal,
      idle_timeout: this.idle_timeout_sec,
      enable_http2: this.enable_http2,
      desync_mitigation_mode: this.desync_mitigation_mode,
    },

    LoadBalancerType: {
      APPLICATION: 'application',
      GATEWAY: 'gateway',
      NETWORK: 'network',
    },
  },

  TargetGroup: aws.RegionResource + {
    local this = self,

    type: 'aws_lb_target_group',
    tag: 'alb_target_group',
    vpc: null,
    target_type: 'ip',
    port: 80,
    protocol: 'HTTP',
    load_balancing_algorithm_type: "round_robin",
    health_check: null,

    depends_on+: [this.vpc] + this.subnets + this.security_groups,
    args+: {
      name: this.tag,
      subnets: [x.id() for x in this.subnets],
      security_groups: [x.id() for x in this.security_groups],
      internal: this.internal,
      idle_timeout: this.idle_timeout_sec,
      enable_http2: this.enable_http2,
      desync_mitigation_mode: this.desync_mitigation_mode,
    },
  },

  HealthCheck: {
    path: "/",
    protocol: "HTTP",
    healthy_threshold: 5,
    unhealthy_threshold: 2,
    timeout_sec: 5,
    interval_sec: 30,
    matcher: 200,
  },

  Listener: aws.RegionResource + {
    type: 'aws_lb_listener',
    tag: 'lb_listener',
    load_balancer: null,
    target_group: null,
    port: 80,
    protocol: 'HTTP',
  },
}