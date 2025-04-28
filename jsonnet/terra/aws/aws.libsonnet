local core = import 'common/core.libsonnet';
local lang = import 'common/lang.libsonnet';
local terra = import 'common/terra.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  AWS_PROVIDER_SLUG: 'aws',

  Provider: terra.Provider + {
    local this = self,

    slug: $.AWS_PROVIDER_SLUG,
    version: '>= 5.73',
    profile: null,
    default_provider_block: $.ProviderBlock + {
      region: $.Region.OREGON,
      alias: null,
    },
    provider_block_overlay+: {
      profile: this.profile,
    },
  },

  ProviderBlock: lang.ProviderBlock + $.RegionBlockMixin + {
    local this = self,

    slug:: $.AWS_PROVIDER_SLUG,
    profile: null,
    alias: self.region.slug,

    #args+: {
    #  [utils.ifNotNull(this.profile, 'profile')]: this.profile,
    #},
  },

  TaggedResourceMixin: {
    local this = self,
    tags+: {
      Name: this.label,
    },
    #args+: {
    #  tags+: {
    #    Name: this.label,
    #  },
    #},
    #data_block_type: this.type,
    #data_block_args: {
    #  tags: {
    #    Name: this.label,
    #  },
    #},
  },

  RegionBlockMixin: {
    local this = self,

    region:: null,

    __validate__+:: [{
      name: 'aws.RegionBlockMixin',
      validators: [
        core.field('region').required().object(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        region::: this.region.id,
      },
    },
  },

  RegionResourceMixin: {
    local this = self,

    region:: null,
    provider_reference: 'aws.%s' % [self.region.slug],

    required_blocks+:: [$.ProviderBlock + {
      region: this.region,
    }],

    __validate__+:: [{
      name: 'aws.RegionResourceMixin',
      validators: [
        core.field('region').required().object(),
      ],
    }],
    #__manifest__+:: {
    #  overlay+: {
    #    region: this.region.id,
    #  },
    #},
  },

  // These don't do anything on their own anymore, keeping them
  // though bc if I change my mind about that I won't have to
  // go renaming everything
  Data: terra.Data,
  GlobalResource: terra.Resource,
  RegionResource: terra.Resource + $.RegionResourceMixin,

  TaggedGlobalResource: $.GlobalResource + $.TaggedResourceMixin,
  TaggedRegionResource: $.RegionResource + $.TaggedResourceMixin,

  GlobalBundle: terra.Bundle,
  RegionBundle: terra.Bundle + {
    local this = self,
    region: null,
    common_child_opts+: {
      region: this.region,
    },

    __validate__+:: [{
      name: 'aws.RegionBundle',
      validators: [
        core.field('region').required().object(),
      ],
    }],
  },

  Region: {
    N_VIRGINIA: {
      id: 'us-east-1',
      slug: 'use1',
    },
    OHIO: {
      id: 'us-east-2',
      slug: 'use2',
    },
    N_CALIFORNIA: {
      id: 'us-west-1',
      slug: 'usw1',
    },
    OREGON: {
      id: 'us-west-2',
      slug: 'usw2',
    },
  },

  AvailabilityZoneData: terra.Data + {
    local this = self,

    type:: 'aws_availability_zones',
    tag:: 'availability_zones',

    state: 'available',
    opt_in_status:: 'opt-in-not-required',

    filters+: utils.singletonArrayIf(this.opt_in_status != null, {
      name: 'opt-in-status',
      values: [this.opt_in_status],
    }),

    #args+: {
    #  [utils.ifNotNull(this.state, 'state')]: this.state,
    #  [utils.ifNotNull(this.opt_in_status, 'filter')]: {
    #    name: 'opt-in-status',
    #    values: [this.opt_in_status],
    #  },
    #},
  },
}
