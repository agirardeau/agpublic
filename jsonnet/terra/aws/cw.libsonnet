// Templates for CloudWatch resources
local aws = import 'common/aws/aws.libsonnet';
local core = import 'common/core.libsonnet';
local terra = import 'common/terra.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  LogGroup: aws.RegionResource + {
    local this = self,

    type: 'aws_cloudwatch_log_group',
    tag: 'log_group',
    name: null,
    retention_days: null,

    __validate__+:: [{
      name: 'cw.LogGroup',
      validators: [
        core.field('name').required().string(),
        core.field('retention_days').required().number(),
      ],
    }],

    args+: {
      name: this.name,
      retention_in_days: this.retention_days,
    },
  },

  LogStream: aws.RegionResource + {
    local this = self,

    type: 'aws_cloudwatch_log_stream',
    tag: 'log_stream',
    name: null,
    log_group_name: null,

    __validate__+:: [{
      name: 'cw.LogStream',
      validators: [
        core.field('name').required().string(),
        core.field('log_group_name').required().string(),
      ],
    }],

    args+: {
      name: this.name,
      log_group_name: this.log_group_name,
    },
  },

  LogConfiguration: {
    local this = self,
    log_driver:: 'awslogs',
    log_group:: null,
    stream_prefix:: null,
    create_group:: false,
    options: {
      [utils.ifTrue(this.create_group, 'awslogs-create-group')]: true,
      ['awslogs-region']: this.log_group.region.id,
      ['awslogs-group']: this.log_group.name,
      ['awslogs-stream-prefix']: this.stream_prefix,
    },
    logDriver: self.log_driver,
  },
}