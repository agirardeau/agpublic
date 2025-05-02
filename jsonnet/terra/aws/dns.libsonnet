local agw = import 'common/aws/agw.libsonnet';
local aws = import 'common/aws/aws.libsonnet';
local core = import 'common/core.libsonnet';
local lang = import 'common/lang.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  // It might be nice to manage domains in Terraform, but then a bunch of
  // registrant contact information has to be added to the config when it would
  // be easier to just keep it in the UI. The benefit of managing it in
  // terraform is mostly that the name servers could be automatically set to the
  // ones used by the hosted zone. Setting them in the AWS console is easy, but
  // it's even easier to forget or not realize that needs to happen,
  //
  // This resource doesn't register a domain, only brings an existing domain
  // under terraform management
  #RegisteredDomain: aws.GlobalResource + {
  #  local this = self,
  #
  #  type: 'aws_route53domains_registered_domain',
  #  tag: 'registered_domain',
  #  domain_name: null,
  #  name_servers: [],  // Array (jsonnet *or* hcl) of name server fqdns
  #
  #  validate()::
  #    assert self.domain_name != null : 'HostedZone: Domain name not specified';
  #    super.validate(),
  #
  #  args+: {
  #    domain_name: this.domain_name
  #    [utils.ifNotEmpty(this.name_servers, 'name_server')]:
  #      if std.type(this.name_servers) == 'array' then [
  #        { name: ns }
  #        for ns in this.name_servers
  #      ]
  #      else if std.type(this.name_servers) == 'string' then this.name_servers
  #      else error 'Wrong type: %s' % [std.type(this.nameservers)],
  #  },
  #},

  HostedZone: aws.GlobalResource + {
    local this = self,

    type: 'aws_route53_zone',
    tag: 'hosted_zone',
    domain_name: null,  // Domain name, e.g. `example.com`

    validate()::
      assert self.domain_name != null : 'HostedZone: Domain name not specified';
      super.validate(),

    args+: {
      name: this.domain_name,
    },
  },

  Record: aws.GlobalResource + {
    local this = self,

    type: 'aws_route53_record',
    tag: 'route53_record',
    attributes+: ['fqdn'],
    domain_name: null,  // Aka record name
    hosted_zone: null,
    record_type: null,
    values: [],  // "records" terraform argument, "Value/Route traffic to" in AWS console
    ttl_s: null,
    allow_overwrite: false,

    __validate__+:: [{
      name: 'dns.Record',
      validators: [
        core.field('domain_name').required().string(),
        core.field('hosted_zone').required().object(),
        core.field('record_type').required().string(),
      ],
    }],

    depends_on+: [
      this.hosted_zone,
    ],
    args+: {
      name: this.domain_name,
      zone_id: this.hosted_zone.id(),
      type: this.record_type,
      [utils.ifNotEmpty(this.values, 'records')]: this.values,
      [utils.ifNotNull(this.ttl_s, 'ttl')]: this.ttl_s,
      [utils.ifTrue(this.allow_overwrite, 'allow_overwrite')]: this.allow_overwrite,
    },

    RecordType: {
      A: 'A',
      AAAA: 'AAAA',
      CAA: 'CAA',
      CNAME: 'CNAME',
      DS: 'DS',
      MX: 'MX',
      NAPTR: 'NAPTR',
      NS: 'NS',
      PTR: 'PTR',
      SOA: 'SOA',
      SPF: 'SPF',
      SRV: 'SRV',
      TXT: 'TXT',
    },
  },

  AliasRecord: $.Record + {
    local this = self,

    tag: 'route53_alias_record',
    target: null,
    record_type: $.Record.RecordType.A,
    evaluate_target_health: false,

    __validate__+:: [{
      name: 'dns.AliasRecord',
      validators: [
        core.field('target').required().object().check(function(x)
          if x.type != agw.ApiGatewayV2Domain.type
          then 'ApiGatewayV2Domain is the only supported target type currently'
          else null
        ),
      ],
    }],

    args+: {
      alias: {
        name: this.target.attribute('domain_name_configuration[0].target_domain_name'),
        zone_id: this.target.attribute('domain_name_configuration[0].hosted_zone_id'),
        evaluate_target_health: this.evaluate_target_health
      },
    },

    #Details: core.Object + {
    #  target_domain_name:: null,
    #  hosted_zone:: null,
    #  evaluate_target_health: false,

    #  validate()::
    #    assert self.target_domain_name != null : 'Record.Details: Target domain name not specified';
    #    assert self.hosted_zone != null : 'Record.Details: Hosted zone not specified';
    #    super.validate(),

    #  name: self.target_domain_name,
    #  zone_id: self.hosted_zone.id(),
    #},
  },

  // Creating certificates in ACM is a weird process, after requesting one
  // it will be "Pending Validation" until you create a particular DNS record
  // that proves you have ownership.
  // There's a nice "Create records in Route 53" button on the UI for this,
  // or certificate_bundle and then make the certs (or dns records, but idk
  // why) terraform managed using the `import_by` field after the fact.
  // https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html
  Certificate: aws.RegionResource + {
    local this = self,

    type: 'aws_acm_certificate',
    tag: 'certificate',
    attributes+: ['arn'],
    domain_name: null,
    is_wildcard: true,
    subject_alternative_names: utils.singletonArrayIf(self.is_wildcard, '*.%s' % [self.domain_name]), 
    validation_method: 'DNS',

    __validate__+:: [{
      name: 'dns.Certificate',
      validators: [
        core.field('domain_name').required().string(),
      ],
    }],

    lifecycle+: {
      create_before_destroy: true,
    },
    args+: {
      domain_name: this.domain_name,
      subject_alternative_names: this.subject_alternative_names,
      validation_method: this.validation_method,
    },
  },

  CertificateValidationRecord: $.Record + {
    local this = self,

    tag: '%s_validation_record' % [self.certificate.tag],
    certificate: null,
    for_each: lang.ForEach + {
      raw_expression: |||
        {
          for dvo in %s : dvo.domain_name => {
            name  = dvo.resource_record_name
            value = dvo.resource_record_value
            type  = dvo.resource_record_type
          }
        }
      ||| % [this.certificate.attributeUnwrapped('domain_validation_options')],
    },

    domain_name: lang.Each.attribute('value.name'),
    record_type: lang.Each.attribute('value.type'),
    values: [lang.Each.attribute('value.value')],
    ttl_s: 300,
    allow_overwrite: true,

    __validate__+:: [{
      name: 'dns.CertificateValidationRecord',
      validators: [
        core.field('certificate').required().object(),
      ],
    }],
  },

  CertificateValidation: aws.GlobalResource + {
    local this = self,

    type: 'aws_acm_certificate_validation',
    tag: 'certificate_validation',
    certificate: null,
    record: null,

    __validate__+:: [{
      name: 'dns.CertificateValidation',
      validators: [
        core.field('certificate').required().object(),
        core.field('record').required().object().check(function(x)
          if x.for_each == null
          then 'DNS record should be for_each'
          else null
        ),
      ],
    }],

    args+: {
      certificate_arn: this.certificate.attribute('arn'),
      validation_record_fqdns: '${[for r in %s : r.fqdn]}' % [this.record.reference_string],
      #validation_record_fqdns: '${%s}' % [
      #  std.join(
      #    ' + ',
      #    ['[for r in %s : r.fqdn]']
      #    [r.attributeUnwrapped('fqdn') for r in this.records],
      #  ),
      #],
    },
  },

  CertificateBundle: aws.RegionBundle + {
    local this = self,

    domain_name: null,
    hosted_zone: null,

    certificate: $.Certificate + this.common_child_opts + {
      domain_name: this.domain_name,
    },
    validation_record: $.CertificateValidationRecord + this.common_child_opts + {
      certificate: this.certificate,
      hosted_zone: this.hosted_zone,
    },
    validation: $.CertificateValidation + this.common_child_opts + {
      certificate: this.certificate,
      record: this.validation_record,
    },

    __validate__+:: [{
      name: 'dns.CertificateBundle',
      validators: [
        core.field('domain_name').required().string(),
        core.field('hosted_zone').required().object(),
      ],
    }],

    children: utils.flatten([
      this.certificate,
      this.validation_record,
      this.validation,
    ]),
  },

  CloudMapNamespace: aws.GlobalResource + {
    local this = self,

    type: 'aws_service_discovery_private_dns_namespace',
    tag: 'cloud_map_namespace',
    vpc: null,
    name: null,

    __validate__+:: [{
      name: 'dns.CloudMapNamespace',
      validators: [
        core.field('name').required().string(),
        core.field('vpc').required().object(),
      ],
    }],

    depends_on+: [
      this.vpc,
    ],
    args+: {
      vpc: this.vpc.id(),
      name: this.name,
    },
  },

  CloudMapService: aws.GlobalResource + {
    local this = self,

    type: 'aws_service_discovery_service',
    tag: 'cloud_map_service',
    attributes+: ['arn'],
    name: null,
    dns_config: this.DnsConfig,

    __validate__+:: [{
      name: 'dns.CloudMapService',
      validators: [
        core.field('name').required().string(),
        core.field('dns_config').object().child(),
      ],
    }],

    depends_on+: [
      this.dns_config.cloud_map_namespace,
    ],
    args+: {
      name: this.name,
      dns_config: this.dns_config,
    },

    DnsConfig: core.Object + {
      cloud_map_namespace:: null,
      dns_records: [],

      __validate__+:: [{
        name: 'dns.CloudMapService.DnsConfig',
        validators: [
          core.field('cloud_map_namespace').required().object(),
          core.field('dns_records').arrayOfObject().children(),
        ],
      }],

      namespace_id: self.cloud_map_namespace.id(),
    },

    DnsRecord: core.Object + {
      ttl_s:: null,
      record_type:: null,

      __validate__+:: [{
        name: 'dns.CloudMapService.DnsRecord',
        validators: [
          core.field('ttl_s').required().number(),
          core.field('record_type').required().string(),
        ],
      }],

      ttl: self.ttl_s,
      type: self.record_type,
    },
  },
}
