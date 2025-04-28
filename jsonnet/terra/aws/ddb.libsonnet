// Templates for DynamoDB resources
local aws = import 'common/aws/aws.libsonnet';
local core = import 'common/core.libsonnet';
local terra = import 'common/terra.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  Table: aws.RegionResource + aws.TaggedResourceMixin + {
    local this = self,

    type:: 'aws_dynamodb_table',
    tag:: 'dynamodb_table',
    table_name: null,
    hash_key: null,
    hash_key_type:: this.AttributeType.STRING,
    attributes: [this.Attribute + {
      name: this.hash_key,
      type: this.hash_key_type,
    }],
    read_capacity: null,
    write_capacity: null,

    __validate__+:: [{
      name: 'ddb.Table',
      validators: [
        core.field('table_name').required().string(),
        core.field('hash_key').required().string(),
        core.field('hash_key_type').string(),
        core.field('read_capacity').number(),
        core.field('write_capacity').number(),
        core.field('attributes').children(),
      ],
    }],
    __manifest__+:: {
      rename+: {
        table_name: 'name',
        attributes: 'attribute',
      },
    },

    #args+: {
    #  name: this.table_name,
    #  hash_key: this.hash_key,
    #  attribute: this.attributes,
    #  [utils.ifNotNull(this.read_capacity, 'read_capacity')]: this.read_capacity,
    #  [utils.ifNotNull(this.write_capacity, 'write_capacity')]: this.write_capacity,
    #},

    Attribute:: core.Object + {
      name: null,
      type: null,
    },

    AttributeType:: {
      STRING: 'S',
      NUMBER: 'N',
      BINARY: 'B',
    },
  },
}