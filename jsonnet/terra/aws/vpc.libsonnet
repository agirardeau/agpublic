local aws = import 'common/aws/aws.libsonnet';
local ec2 = import 'common/aws/ec2.libsonnet';
local lang = import 'common/lang.libsonnet';
local terra = import 'common/terra.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  Vpc: aws.RegionResource + {
    local this = self,

    type: 'aws_vpc',
    tag: 'vpc',
    cidr_block: $.CidrBlock.DEFAULT_VPC,

    args+: {
      cidr_block: this.cidr_block,
    },
  },

  Subnet: aws.RegionResource + {
    local this = self,

    type: 'aws_subnet',
    tag: 'subnet',
    vpc: null,
    newbits: null,
    netnum: null,

    validate()::
      assert self.vpc != null : 'Subnet: VPC not specified';
      assert self.newbits != null : 'Subnet: Newbits not specified';
      assert self.netnum != null : 'Subnet: Netnum not specified';
      super.validate(),

    depends_on+: [
      this.vpc,
    ],
    args+: {
      vpc_id: this.vpc.id(),
      cidr_block: terra.Std.cidrsubnet(this.vpc.cidr_block, this.newbits, this.netnum),
    },
  },

  RouteTable: aws.RegionResource + {
    local this = self,

    type: 'aws_route_table',
    tag: 'route_table',
    vpc: null,

    depends_on+: [
      this.vpc,
    ],
    args+: {
      vpc_id: this.vpc.id(),
    },
  },

  // Associates a Route Table with a Subnet
  RouteTableAssociation: aws.RegionResource + {
    local this = self,

    type: 'aws_route_table_association',
    tag: 'route_association',
    route_table: null,
    subnet: null,

    validate()::
      assert self.route_table != null : 'RouteTableAssociation: Route Table not specified';
      assert self.subnet != null : 'RouteTableAssociation: Subnet not specified';
      super.validate(),

    depends_on+: [
      this.route_table,
      this.subnet,
    ],
    args+: {
      route_table_id: this.route_table.id(),
      subnet_id: this.subnet.id(),
    },
  },

  // Adds a Route in a given Route Table to a given destination
  Route: aws.RegionResource + {
    local this = self,

    type: 'aws_route',
    tag: 'route',
    route_table: null,
    destination: null,  // Resource instance
    destination_cidr_block: null,

    local destination_id_arg_by_type = {
      'aws_internet_gateway': 'gateway_id',
      'aws_nat_gateway': 'nat_gateway_id',
    },

    validate()::
      assert self.route_table != null : 'Route: Route Table not specified';
      assert self.destination_cidr_block != null : 'Route: Destination CIDR block not specified';
      assert self.destination != null: 'Route: Destination resource not specified';
      assert std.objectHas(destination_id_arg_by_type, self.destination.type) :
        'Route: Destination resource type `%s` not supported, expected one of %s' % [
          self.destination.type,
          std.objectFields(destination_id_arg_by_type),
        ];
      super.validate(),

    depends_on+: [
      this.route_table,
      this.destination,
    ],
    args+: {
      route_table_id: this.route_table.id(),
      [destination_id_arg_by_type[this.destination.type]]: this.destination.id(),
      destination_cidr_block: this.destination_cidr_block,
    },
  },

  ElasticIp: aws.RegionResource + {
    local this = self,

    type: 'aws_eip',
    tag: 'elastic_ip',
    domain: 'vpc',

    args+: {
      domain: this.domain,
    },
  },

  InternetGateway: aws.RegionResource + {
    type: 'aws_internet_gateway',
    tag: 'internet_gateway',
  },

  // Attaches an Internet Gateway to a VPC
  InternetGatewayAttachment: aws.RegionResource + {
    local this = self,

    type: 'aws_internet_gateway_attachment',
    tag: 'internet_gateway_attachment',
    vpc: null,
    internet_gateway: null,

    validate()::
      assert self.vpc != null : 'InternetGatewayAttachment: VPC not specified';
      assert self.internet_gateway != null : 'InternetGatewayAttachment: Internet Gateway not specified';
      super.validate(),

    depends_on+: [
      this.vpc,
      this.internet_gateway,
    ],
    args+: {
      internet_gateway_id: this.internet_gateway.id(),
      vpc_id: this.vpc.id(),
    },
  },

  // NAT Gateways allow outbound traffic to the internet for resources in
  // private subnets, but cost $33/month.
  // Note that RDS obviates the database's need an outbound internet
  // connection since it manages updates and maintenance, see
  // https://serverfault.com/questions/942746/does-rds-in-private-subnet-inside-aws-vpc-need-a-nat-instance-gateway.
  // Security group rules can be used instead to prevent inbound traffic to
  // resources that should be isolated like databases.
  // https://www.reddit.com/r/aws/comments/tcr9bf/do_i_need_a_private_subnet_and_a_nat_gateway_if/
  NatGateway: aws.RegionResource + {
    local this = self,

    type: 'aws_nat_gateway',
    tag: 'nat_gateway',
    elastic_ip: null,
    subnet: null,

    validate()::
      assert self.elastic_ip != null : 'NatGateway: Elastic IP not specified';
      assert self.subnet != null : 'NatGateway: Subnet not specified';
      super.validate(),

    depends_on+: [
      this.elastic_ip,
      this.subnet,
    ],
    args+: {
      allocation_id: this.elastic_ip.id(),
      subnet_id: this.subnet.id(),
    },
  },

  // Subnet Terminology:
  //   Public subnet: Route table has a route from 0.0.0.0/0 to an internet
  //       gateway, which causes resources in the subnet to have public IP
  //       addresses. Resources can make outbound calls and receive inbound
  //       traffic, only restricted by security group settings.
  //   Private subnet: Route table has a route from 0.0.0.0/0 to a NAT
  //       gateway. Resources have no public IP addresses, and thus cannot
  //       make outbound calls or receive inbound traffic directly. Outbound
  //       calls can be made by proxying through the NAT gateway, inbound
  //       traffic must be routed through an API Gateway or ALB in a public
  //       subnet.
  //   Isolated subnet: Route table has no route for 0.0.0.0/0. Inbound and
  //       outbound traffic can only occur with other resources inside the
  //       VPC.
  SubnetBundle: aws.RegionBundle + {
    local this = self,

    vpc: null,
    newbits: null,
    netnum: null,
    // TODO - Add ability to specify multiple availability zones. Unless using
    // NAT Gateways, it's preferable to have only one route table per zone. With
    // NAT Gateways, each AZ probably wants its own NAT Gateway for redundancy,
    // so it's preferable to have a route table per AZ as well. It's also
    // necessary to have different route tables for subnets with different
    // isolation properties (e.g. public vs private).
    // https://stackoverflow.com/a/66255243
    //availability_zones: [],
    //azs_share_route_table: true,  // If true, one route table per tier, otherwise one per tier+az

    validate()::
      assert self.vpc != null : 'SubnetBundle: VPC not specified';
      assert self.newbits != null : 'SubnetBundle: Newbits not specified';
      assert self.newbits != null : 'SubnetBundle: Netnum not specified';
      super.validate(),

    subnet: $.Subnet + this.common_child_opts + {
      vpc: this.vpc,
      newbits: this.newbits,
      netnum: this.netnum,
    },
    route_table: $.RouteTable + this.common_child_opts + {
      vpc: this.vpc,
    },
    route_association: $.RouteTableAssociation + this.common_child_opts + {
      subnet: this.subnet,
      route_table: this.route_table,
    },
    children: [
      this.subnet,
      this.route_table,
      this.route_association,
    ],
  },

  PublicSubnetBundle: $.SubnetBundle + {
    local this = self,

    internet_gateway: $.InternetGateway + this.common_child_opts,
    internet_gateway_attachment: $.InternetGatewayAttachment + this.common_child_opts + {
      vpc: this.vpc,
      internet_gateway: this.internet_gateway,
    },
    internet_route: $.Route + this.common_child_opts +{
      tag: 'internet_route',
      route_table: this.route_table,
      destination: this.internet_gateway,
      destination_cidr_block: $.CidrBlock.ALL_IPS_IPV4,
    },
    children+: [
      this.internet_gateway,
      this.internet_gateway_attachment,
      this.internet_route,
    ],
  },

  // TODO: Set this up to use fck-nat rather than NAT gateway to reduce cost
  // from $33/month to $3/month
  PrivateSubnetBundle: $.SubnetBundle + {
    local this = self,

    public_subnet_bundle: null,
    use_fck_nat: false,

    validate()::
      assert this.public_subnet_bundle != null : 'PrivateSubnetBundle: Public subnet bundle not specified (needed to place NAT gateways)';
      super.validate(),

    elastic_ip: $.ElasticIp + this.common_child_opts,
    nat_gateway: utils.ifTrue(!self.use_fck_nat, $.NatGateway + this.common_child_opts + {
      elastic_ip: this.elastic_ip,
      subnet: this.public_subnet_bundle.subnet,
    }),
    internet_route: utils.ifTrue(!self.use_fck_nat, $.Route + this.common_child_opts + {
      tag: 'internet_route',
      route_table: this.route_table,
      destination: this.nat_gateway,
      destination_cidr_block: $.CidrBlock.ALL_IPS_IPV4,
    }),
    fck_nat: utils.ifTrue(self.use_fck_nat, $.FckNatModule + {
      name: 'fck_nat',
      vpc: this.vpc,
      subnet: this.public_subnet_bundle.subnet,
      route_tables: [this.route_table],
    }),

    children+: [
      this.elastic_ip,
      utils.ifTrue(!this.use_fck_nat, this.nat_gateway),
      utils.ifTrue(!this.use_fck_nat, this.internet_route),
      // TODO: make it so that fck-nat module can be included here?
    ],
  },

  // Currently only has options for a "Gateway" private link, since "Interface"
  // private links cost $7/month (wtfffffff)
  VpcEndpoint: aws.RegionResource + {
    local this = self,

    type: 'aws_vpc_endpoint',
    tag: 'vpc_endpoint_%s' % [self.service_slug],
    vpc_endpoint_type: 'Gateway',
    vpc: null,
    service_slug: null,  // 's3', 'ecr', etc
    service_name: 'com.amazonaws.%s.%s' % [self.region.id, self.service_slug],
    route_tables: [],

    validate()::
      assert self.vpc != null : 'VpcEndpoint: VPC not specified';
      assert self.service_name != null : 'VpcEndpoint: Service slug/name not specified';
      super.validate(),

    args+: {
      vpc_id: this.vpc.id(),
      service_name: this.service_name,
      route_table_ids: [t.id() for t in this.route_tables],
    },
  },

  local IngressEgressRule = aws.GlobalResource + {
    local this = self,

    security_group: null,
    ip_protocol: $.IpProtocol.TCP,
    from_port: null,
    to_port: null,
    cidr_ipv4: null,
    cidr_ipv6: null,
    referenced_security_group: null,

    validate()::
      assert self.security_group != null : 'IngressEgressRule: Security group not specified';
      assert self.from_port != null || self.ip_protocol == $.IpProtocol.ANY : 'IngressEgressRule: From port not specified';
      assert self.to_port != null || self.ip_protocol == $.IpProtocol.ANY : 'IngressEgressRule: To port not specified';
      assert self.cidr_ipv4 != null || self.cidr_ipv6 != null || self.referenced_security_group != null :
        'IngressEgressRule: Traffic source/destination not specified, expected one of `cidr_ipv4`, `cidr_ipv6`, or `referenced_security_group`.';
      super.validate(),

    depends_on+: [
      this.security_group,
    ] + (
      if this.referenced_security_group != null
      then [this.referenced_security_group]
      else []
    ),
    args+: {
      [utils.ifNotNull(this.cidr_ipv4, 'cidr_ipv4')]: this.cidr_ipv4,
      [utils.ifNotNull(this.cidr_ipv6, 'cidr_ipv6')]: this.cidr_ipv6,
      [utils.ifNotNull(this.referenced_security_group, 'referenced_security_group_id')]:
        this.referenced_security_group.id(),
      ip_protocol: this.ip_protocol,
      from_port: this.from_port,
      to_port: this.to_port,
      security_group_id: this.security_group.id(),
    },
  },

  IngressRule: IngressEgressRule + {
    type: 'aws_vpc_security_group_ingress_rule',
    tag: 'ingress_rule',
    source_security_group: null,
    referenced_security_group: self.source_security_group,
  },

  EgressRule: IngressEgressRule + {
    type: 'aws_vpc_security_group_egress_rule',
    tag: 'egress_rule',
    destination_security_group: null,
    referenced_security_group: self.destination_security_group,
  },

  SecurityGroup: aws.GlobalResource + {
    local this = self,

    type: 'aws_security_group',
    tag: 'security_group',
    vpc: null,

    validate()::
      assert self.vpc != null : 'SecurityGroup: VPC not specified';
      super.validate(),

    depends_on: [
      self.vpc,
    ],
    args+: {
      vpc_id: this.vpc.id(),
    },
  },

  IpProtocol: {
    ANY: '-1',
    TCP: 'tcp',
  },

  CidrBlock: {
    ALL_IPS_IPV4: '0.0.0.0/0',
    ALL_IPS_IPV6: '::/0',
    DEFAULT_VPC: '10.0.0.0/16',
  },

  #Port: {
  #  ANY: 0,
  #  HTTP: 80,
  #},

  // Cheaper ($3-$4) replacement for NAT gateway that can also be used for
  // other stuff like a bastion host
  FckNatBundle: aws.RegionBundle + {
    local this = self,

    tag: 'fck_nat',
    subnet: null,  // TODO: validation
    security_groups: [],

    ami: $.RegisteredAmi + self.common_child_opts + {
      args+: {
        filter: [{
          name: 'name',
          values: ['fck-nat-al2023-*'],
        }, {
          name: 'architecture',
          values: ['arm64'],
        }],
        owners: ['568608671756'],
        most_recent: true,
      },
    },
    instance: $.Instance + self.common_child_opts + {
      ami: this.ami,
      network_interface: this.network_interface,
      args+: {
        instance_type: 't4g.nano',
        network_interface+: {
          device_index: 0,
        },
      },
    },
    network_interface: $.NetworkInterface + self.common_child_opts + {
      subnet: this.subnet,
      security_groups: this.security_groups,
      args+: {
        source_dest_check: false,
      },
    },
    children: [
      this.ami,
      this.instance,
      this.network_interface,
    ],
  },

  FckNatModule: lang.ModuleBlock + {
    local this = self,

    source: 'RaJiska/fck-nat/aws',
    name: null,
    vpc: null,
    subnet: null,
    route_tables: [],

    args+: {
      name: this.name,
      vpc_id: this.vpc.id(),
      subnet_id: this.subnet.id(),
      update_route_tables: std.length(this.route_tables) > 0,
      route_tables_ids: {
        [t.label]: t.id()
        for t in this.route_tables
      },
    },
  },
}
