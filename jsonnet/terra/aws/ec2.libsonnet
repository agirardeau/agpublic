local aws = import 'common/aws/aws.libsonnet';
local dns = import 'common/aws/dns.libsonnet';
local vpc = import 'common/aws/vpc.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  RegisteredAmi: aws.Data + {
    type: 'aws_ami',
    tag: 'ami',
  },

  Instance: aws.RegionResource + {
    local this = self,

    type: 'aws_instance',
    tag: 'instance',
    ami: null,
    network_interface: null,  // TODO: validation

    args+: {
      ami: this.ami.id(),
      network_interface_id: this.network_interface.id(),
    }
  },

  NetworkInterface: aws.RegionResource + {
    local this = self,

    type: 'aws_network_interface',
    tag: 'network_interface',
    subnet: null,  // TODO: validation
    security_groups: [],

    args+: {
      subnet_id: this.subnet.id(),
      security_groups: [g.id() for g in this.security_groups],
    },
  },
}