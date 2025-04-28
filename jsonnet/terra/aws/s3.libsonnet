// Templates for Simple Storage Service resources
local aws = import 'common/aws/aws.libsonnet';
local ddb = import 'common/aws/ddb.libsonnet';
local core = import 'common/core.libsonnet';
local terra = import 'common/terra.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  Bucket: aws.TaggedRegionResource + {
    local this = self,

    type:: 'aws_s3_bucket',
    tag:: 'bucket',
    bucket_name: null,

    __validate__+:: [{
      name: 's3.Bucket',
      validators: [
        core.field('bucket_name').required().string(),
      ],
    }],
    __manifest__+:: {
      rename+: {
        bucket_name: 'bucket',
      },
    },
  },

  BucketVersioning: aws.RegionResource + {
    local this = self,

    type:: 'aws_s3_bucket_versioning',
    tag:: 'bucket_versioning',
    bucket_name: null,
    versioning_status:: null,
    mfa_delete_status:: null,
    versioning_configuration: core.Object + {
      status: this.versioning_status,
      mfa_delete: this.mfa_delete_status,
    },

    __validate__+:: [{
      name: 's3.Backend',
      validators: [
        core.field('bucket_name').required().string(),
        core.field('versioning_status').required().string(),
        core.field('mfa_delete_status').string(),
      ],
    }],
    __manifest__+:: {
      rename+: {
        bucket_name: 'bucket',
        lock_table_name: 'dynamodb_table',
      },
    },

    Status:: {
      ENABLED: 'Enabled',
      DISABLED: 'Disabled',
      SUSPENDED: 'Suspended',
    },
  },

  // Terraform bundle defining an S3 bucket and related entities to use as a
  // terraform backend.
  // Generally this should be defined in a config that uses a local backend.
  // TODO: consider adding a policy requiring encryption per answer at
  // https://stackoverflow.com/a/52807063/2547864
  TerraformStateBackendBundle: aws.RegionBundle + {
    local this = self,

    tag: 'terraform_state',
    state_bucket_name: null,
    bucket: $.Bucket + this.common_child_opts + {
      bucket_name: this.state_bucket_name,
      lifecycle+: {
        prevent_destroy: true,
      },
    },
    bucket_versioning: $.BucketVersioning + this.common_child_opts + {
      bucket_name: this.state_bucket_name,
      versioning_status: $.BucketVersioning.Status.ENABLED,
    },
    lock_table: ddb.Table + this.common_child_opts + {
      table_name: 'terraform-lock-table',
      hash_key: 'LockID',
      read_capacity: 1,
      write_capacity: 1,
    },

    __validate__+:: [{
      name: 's3.TerraformStateBackendBundle',
      validators: [
        core.field('state_bucket_name').required().string(),
      ],
    }],

    children: [
      this.bucket,
      this.bucket_versioning,
      this.lock_table,
    ],
    backend: $.Backend + {
      region: this.region,
      bucket_name: this.state_bucket_name,
      lock_table_name: this.lock_table.table_name,
    },
  },

  Backend: terra.Backend + aws.RegionBlockMixin + {
    local this = self,

    backend_type:: 's3',
    bucket_name: null,
    key: null,
    lock_table_name: null,
    profile: null,

    __validate__+:: [{
      name: 's3.Backend',
      validators: [
        core.field('bucket_name').required().string(),
        core.field('key').required().string(),
        core.field('lock_table_name').string(),
        core.field('profile').string(),
      ],
    }],
    __manifest__+:: {
      rename+: {
        bucket_name: 'bucket',
        lock_table_name: 'dynamodb_table',
      },
    },
  },
}