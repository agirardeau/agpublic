local aws = import 'common/aws/aws.libsonnet';
local cw = import 'common/aws/cw.libsonnet';
local dns = import 'common/aws/dns.libsonnet';
local vpc = import 'common/aws/vpc.libsonnet';
local core = import 'common/core.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  Protocol: {
    HTTP: 'HTTP',
    REST: 'REST',
    WEBSOCKET: 'WEBSOCKET',
  },

  ApiGatewayV2: aws.RegionResource + {
    local this = self,

    type: 'aws_apigatewayv2_api',
    tag: 'api_gateway',
    attributes+: ['arn', 'api_endpoint'],
    name: null,
    protocol: null,

    __validate__+:: [{
      name: 'agw.ApiGatewayV2',
      validators: [
        core.field('name').required().string(),
        core.field('protocol').required().string().check(function(x)
          if x == $.Protocol.REST
          then 'REST protocol not supported by API Gateway V2, use API Gateway V1 instead'
          else null
        ),
      ],
    }],

    args+: {
      name: this.name,
      protocol_type: this.protocol,
    },
  },

  ApiGatewayV2Domain: aws.RegionResource + {
    local this = self,

    type: 'aws_apigatewayv2_domain_name',
    tag: 'api_gateway_domain',
    domain_name: null,
    certificate_bundle: null,

    __validate__+:: [{
      name: 'agw.ApiGatewayV2Domain',
      validators: [
        core.field('domain_name').required().string(),
        core.field('certificate_bundle').required().object(),
      ],
    }],

    depends_on+: [
      this.certificate_bundle.validation,
    ],
    args: {
      domain_name: this.domain_name,
      domain_name_configuration: {
        certificate_arn: this.certificate_bundle.certificate.attribute('arn'),
        endpoint_type: 'REGIONAL',  // As of 2024.10.27 no other values are allowed
        security_policy: 'TLS_1_2',  // As of 2024.10.27 no other values are allowed
      },
    },
  },

  ApiGatewayV2Stage: aws.RegionResource + {
    local this = self,

    type: 'aws_apigatewayv2_stage',
    tag: 'api_gateway_stage',
    name: null,
    gateway: null,

    __validate__+:: [{
      name: 'agw.ApiGatewayV2Stage',
      validators: [
        core.field('name').required().string(),
        core.field('gateway').required().object(),
      ],
    }],

    depends_on+: [
      this.gateway,
    ],
    args+: {
      name: this.name,
      api_id: this.gateway.id(),
    },
  },

  // Maps a domain to a given API Gateway stage
  ApiGatewayV2Mapping: aws.RegionResource + {
    local this = self,

    type: 'aws_apigatewayv2_api_mapping',
    tag: 'api_gateway_mapping',
    gateway: null,
    domain: null,
    stage: null,

    __validate__+:: [{
      name: 'agw.ApiGatewayV2Mapping',
      validators: [
        core.field('gateway').required().object(),
        core.field('domain').required().object(),
        core.field('stage').required().object(),
      ],
    }],

    depends_on+: [
      this.gateway,
      this.domain,
      this.stage,
    ],
    args+: {
      api_id: this.gateway.id(),
      domain_name: this.domain.id(),
      stage: this.stage.id(),
    },
  },

  // TODO: split out stage/mapping so that different stages can point to
  // different resources?
  ApiGatewayV2Bundle: aws.RegionBundle + {
    local this = self,

    name: null,
    domain_name: null,
    hosted_zone: null,
    certificate_bundle: null,

    __validate__+:: [{
      name: 'agw.ApiGatewayV2Bundle',
      validators: [
        core.field('name').required().string(),
        core.field('domain_name').required().string(),
        core.field('hosted_zone').required().object(),
        core.field('certificate_bundle').required().object(),
      ],
    }],

    gateway: $.ApiGatewayV2 + this.common_child_opts + {
      name: this.name,
      protocol: $.Protocol.HTTP,
    },
    domain: $.ApiGatewayV2Domain + this.common_child_opts + {
      domain_name: this.domain_name,
      certificate_bundle: this.certificate_bundle,
    },
    stage: $.ApiGatewayV2Stage + this.common_child_opts + {
      name: 'main',
      gateway: this.gateway,
      args+: {
        access_log_settings+: {
          destination_arn: this.activity_log_group.attribute('arn'),
          format: std.strReplace(std.strReplace(|||
            {
              "requestId":"$context.requestId",
              "ip": "$context.identity.sourceIp",
              "requestTime":"$context.requestTime",
              "httpMethod":"$context.httpMethod",
              "routeKey":"$context.routeKey",
              "status":"$context.status",
              "protocol":"$context.protocol",
              "responseLength":"$context.responseLength",
              "extendedRequestId": "$context.extendedRequestId",
              "authorize.status": "$authorize.status",
              "authorize.error": "$authorize.error",
              "integration.error": "$context.integration.error",
              "integration.integrationStatus": "$context.integration.integrationStatus",
              "integration.requestId": "$context.integration.requestId",
              "integration.status": "$context.integration.status"
            }
          |||, '\n', ''), ' ', ''),
        },
        default_route_settings+: {
          detailed_metrics_enabled: true,
          logging_level: 'INFO',
          throttling_burst_limit: 5,
          throttling_rate_limit: 5,
        },
      },
    },
    mapping: $.ApiGatewayV2Mapping + this.common_child_opts + {
      gateway: this.gateway,
      domain: this.domain,
      stage: this.stage,
    },
    route53_record: dns.AliasRecord + this.common_child_opts + {
      domain_name: this.domain_name,
      hosted_zone: this.hosted_zone,
      target: this.domain,
    },
    activity_log_group: cw.LogGroup + this.common_child_opts + {
      tag: 'activity_log_group',
      name: self.label,
      retention_days: 1,
    },

    children: [
      this.gateway,
      this.domain,
      this.mapping,
      this.stage,
      this.route53_record,
      this.activity_log_group,
    ],
  },

  VpcLinkV2: aws.RegionResource + {
    local this = self,

    type: 'aws_apigatewayv2_vpc_link',
    tag: 'api_gateway_vpc_link',
    name: null,
    subnets: [],
    security_groups: [],

    validate()::
      assert self.name != null : 'VpcLinkV2: Name not specified';
      super.validate(),

    args+: {
      name: this.name,
      subnet_ids: [x.id() for x in this.subnets],
      security_group_ids: [x.id() for x in this.security_groups],
    },
  },

  // TODO: Let this integrate with things other than VPC links
  ApiGatewayV2Integration: aws.RegionResource + {
    local this = self,

    type: 'aws_apigatewayv2_integration',
    tag: 'api_gateway_integration',
    gateway: null,
    vpc_link: null,
    cloud_map_service: null,
    connection_type: null,
    integration_type: null,
    integration_method: 'ANY',  // HTTP method
    payload_format_version: '1.0',

    __validate__+:: [{
      name: 'agw.ApiGatewayV2Integration',
      validators: [
        core.field('gateway').required().object(),
        core.field('vpc_link').required().object(),
        core.field('cloud_map_service').required().object(),
        core.field('connection_type').required().string(),
        core.field('integration_type').required().string(),
      ],
    }],

    validate()::
      assert self.gateway != null : 'ApiGatewayV2Integration: API gateway not specified';
      assert self.vpc_link != null : 'ApiGatewayV2Integration: VPC link not specified';
      assert self.cloud_map_service != null : 'ApiGatewayV2Integration: CloudMap service not specified';
      assert self.connection_type != null : 'ApiGatewayV2Integration: Connection type not specified';
      assert self.integration_type != null : 'ApiGatewayV2Integration: Integration type not specified';
      super.validate(),

    depends_on+: [
      this.gateway,
    ],
    args+: {
      api_id: this.gateway.id(),
      connection_id: this.vpc_link.id(),
      connection_type: this.connection_type,
      integration_type: this.integration_type,
      integration_method: this.integration_method,
      integration_uri: this.cloud_map_service.attribute('arn'),
      payload_format_version: this.payload_format_version,
    },

    IntegrationType: {
      AWS: 'AWS',
      AWS_PROXY: 'AWS_PROXY',
      HTTP: 'HTTP',
      HTTP_PROXY: 'HTTP_PROXY',
      MOCK: 'MOCK',
    },

    ConnectionType: {
      INTERNET: 'INTERNET',
      VPC_LINK: 'VPC_LINK',
    },
  },

  ApiGatewayV2Route: aws.RegionResource + {
    local this = self,

    type: 'aws_apigatewayv2_route',
    tag: 'api_gateway_route',
    gateway: null,
    integration: null,
    route_key: '$default',  // Either `$default` or HTTP method + path, e.g. `GET /items`

    __validate__+:: [{
      name: 'agw.ApiGatewayV2Route',
      validators: [
        core.field('gateway').required().object(),
        core.field('integration').required().object(),
      ],
    }],

    depends_on+: [
      this.gateway,
      this.integration,
    ],
    args+: {
      api_id: this.gateway.id(),
      route_key: this.route_key,
      target: 'integrations/%s' % [this.integration.id()],
    },
  },

  ApiGatewayV2IntegrationBundle: aws.RegionBundle + {
    local this = self,

    gateway: null,
    cloud_map_namespace: null,
    cloud_map_service_name: null,
    vpc_link: null,
    vpc_link_security_group: null,
    target_security_group: null,
    target_port: null,

    __validate__+:: [{
      name: 'agw.ApiGatewayV2IntegrationBundle',
      validators: [
        core.field('gateway').required().object(),
        core.field('cloud_map_service').required().object(),
        core.field('cloud_map_service_name').required().string(),
        core.field('vpc_link').required().object(),
        core.field('vpc_link_security_group').required().object(),
        core.field('target_security_group').required().object(),
        core.field('target_port').required().number(),
      ],
    }],

    cloud_map_service: dns.CloudMapService + this.common_child_opts + {
      name: this.cloud_map_service_name,
      dns_config+: {
        cloud_map_namespace: this.cloud_map_namespace,
        dns_records: [
          dns.CloudMapService.DnsRecord + {
            record_type: dns.Record.RecordType.SRV,
            ttl_s: 60,
          },
          dns.CloudMapService.DnsRecord + {
            record_type: dns.Record.RecordType.A,
            ttl_s: 10,
          },
        ],
      },
    },
    integration: $.ApiGatewayV2Integration + this.common_child_opts + {
      gateway: this.gateway,
      vpc_link: this.vpc_link,
      cloud_map_service: this.cloud_map_service,
      integration_type: $.ApiGatewayV2Integration.IntegrationType.HTTP_PROXY,
      connection_type: $.ApiGatewayV2Integration.ConnectionType.VPC_LINK,
    },
    route: $.ApiGatewayV2Route + this.common_child_opts + {
      gateway: this.gateway,
      integration: this.integration,
    },
    vpc_link_egress_rule: vpc.EgressRule + this.common_child_opts + {
      security_group: this.vpc_link_security_group,
      destination_security_group: this.target_security_group,
      from_port: this.target_port,
      to_port: this.target_port,
    },
    target_ingress_rule: vpc.IngressRule + this.common_child_opts + {
      security_group: this.target_security_group,
      source_security_group: this.vpc_link_security_group,
      from_port: this.target_port,
      to_port: this.target_port,
    },

    children: [
      this.cloud_map_service,
      this.integration,
      this.route,
      this.vpc_link_egress_rule,
      this.target_ingress_rule,
    ],
  },
}