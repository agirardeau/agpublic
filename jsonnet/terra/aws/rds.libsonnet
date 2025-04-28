// Templates for RDS resources
local aws = import 'common/aws/aws.libsonnet';
local core = import 'common/core.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  SubnetGroup: aws.RegionResource + {
    local this = self,

    type: 'db_subnet_group',
    tag: 'rds_subnet_group',
    name: null,
    subnets: [],

    args+: {
      subnet_ids: [x.id() for x in this.subnets],
    },

    __validate__+: [{
      name: 'rds.SubnetGroup',
      validators: [
        core.field('name').required(),
      ],
    }]
  },

  Instance: aws.RegionResource + {
    local this = self,

    type: 'db_instance',
    tag: 'rds_instance',
    allocated_storage: null,
    engine: null,
    engine_version: null,
    instance_class: 'db.t4g.micro',  // Largest instance type covered in free tier
    master_username: null,
    master_password: null,
    parameter_group: null,
    db_subnet_group: null,
    security_groups+: [],

    __validate__+:: [{
      name: 'rds.Instance',
      validators: [
        core.field('allocated_storage').required(),
        core.field('engine').required().string(),
        core.field('instance_class').required().string(),
        core.field('master_username').required().string(),
      ],
    }],

    args+: {
      allocated_storage: this.allocated_storage,
      engine: this.engine,
      engine_version: this.engine_version,
      instance_class: this.instance_class,
      username: this.master_username,
      password: this.master_password,
      [utils.ifNotNull(this.parameter_group, 'parameter_group_name')]:
        this.parameter_group.name,
      [utils.ifNotNull(this.db_subnet_group, 'db_subnet_group_name')]:
        this.db_subnet_group.name,
      vpc_security_group_ids: [x.id() for x in this.security_groups],
    },
  },

  ParameterGroup: {
    local this = self,

    type: 'aws_db_parameter_group',
    tag: 'rds_parameter_group',
    name: null,
    family: null,
    parameters: {},
    lifecycle+: {
      create_before_destroy: true,
    },

    __validate__+:: [{
      name: 'rds.ParameterGroup',
      validators: [
        core.field('name').required().string(),
        core.field('family').required().string(),
      ],
    }],

    args+: {
      name: this.name,
      family: this.family,
      parameter: [
        {
          name: entry.key,
          value: entry.value,
        }
        for entry in std.objectKeysValues(this.parameters)
      ],
    },
  },
}