local core = import 'common/core.libsonnet';
local terra = import 'common/terra.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  // Represents a top-level block in the terraform config
  Block: core.Object + {
    local this = self,

    block_type:: null,
    dedupe_key:: null,
    is_singleton:: false,
    block_render_info:: self.RenderInfo,
    #args: {},

    __validate__+:: [{
      name: 'lang.Block',
      validators: [
        core.field('block_type').required().string(),
      ],
      debug+: ['block_type'],
    }],

    RenderInfo:: {
      group_by: null,
      key_by: null,
    },

    // Render a set of blocks all with the same block type.
    render(blocks)::
      if std.length(blocks) == 0
      then {}
      else
        #assert std.length(blocks) != 0 : 'Block.render(): No blocks provided';
        assert !blocks[0].is_singleton || std.length(blocks) == 1 : 'Block.render(): Multiple blocks provided for singleton block type `%s`' % [self.block_type];
        local unique_blocks = this.dedupe(blocks);
        local group_by = blocks[0].block_render_info.group_by;
        local key_by = blocks[0].block_render_info.key_by;
        #if group_by == null && key_by == null
        #then [
        #  b.args
        #  for b in unique_blocks
        #]
        #else if group_by == null && key_by != null
        #then {
        #  [b[key_by]]: b.args
        #  for b in unique_blocks
        #}
        #else if group_by != null && key_by == null
        #then {
        #  [entry.key]: [
        #    b.args
        #    for b in entry.value
        #  ]
        #  for entry in std.objectKeysValues(utils.groupByField(unique_blocks, group_by))
        #}
        #else  // group_by != null && key_by != null
        #{
        #  [entry.key]: {
        #    [b[key_by]]: b.args
        #    for b in entry.value
        #  }
        #  for entry in std.objectKeysValues(utils.groupByField(unique_blocks, group_by))
        #},
        if group_by == null && key_by == null
        then unique_blocks
        else if group_by == null && key_by != null
        then {
          [b[key_by]]: b
          for b in unique_blocks
        }
        else if group_by != null && key_by == null
        then {
          [entry.key]: [
            b
            for b in entry.value
          ]
          for entry in std.objectKeysValues(utils.groupByField(unique_blocks, group_by))
        }
        else  // group_by != null && key_by != null
        {
          [entry.key]: {
            [b[key_by]]: b
            for b in entry.value
          }
          for entry in std.objectKeysValues(utils.groupByField(unique_blocks, group_by))
        },

    dedupe(blocks)::
      utils.unique(
        blocks,
        function(b) b.dedupe_key,
        'keep_all',
      ),
  },

  TerraformBlock: $.Block + {
    local this = self,

    block_type:: 'terraform',
    is_singleton:: true,
    required_version: null,
    required_providers: {},
    backend:: null,

    __validate__+:: [{
      name: 'lang.TerraformBlock',
      validators: [
        core.field('required_version').required().string(),
        core.field('backend').object().child(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        # TODO: Figure out why $.Block.render() doesn't return the same value
        # as { [this.backend.backend_type]: this.backend }
        #backend: $.Block.render(utils.singletonArrayIfNotNull(this.backend)),
        backend: {
          [this.backend.backend_type]: this.backend,
        },
      },
    },

    #args+: {
    #  required_version: this.required_version,
    #  required_providers: this.required_providers,
    #  [utils.ifNotNull(this.backend, 'backend')]: this.backend.rendered,
    #},
  },

  ProviderBlock: $.Block + {
    local this = self,

    block_type:: 'provider',
    block_render_info+:: {
      group_by: 'slug',
    },
    dedupe_key:: '%s.%s' % [self.slug, utils.ifNull(self.alias, '')],
    slug:: null,
    alias: null,

    __validate__+:: [{
      name: 'lang.ProviderBlock',
      validators: [
        core.field('slug').required().string(),
      ],
    }],

    #args+: {
    #  [utils.ifNotNull(this.alias, 'alias')]: this.alias,
    #},
  },

  // Common properties of Data and Resource blocks
  EntityBlock: $.Block + {
    local this = self,

    block_render_info+:: {
      group_by: 'type',
      key_by: 'label',
    },
    type:: null,
    label:: null,
    depends_on: [],
    provider: null,
    lifecycle: {},
    for_each: null,

    __validate__+:: [{
      name: 'lang.EntityBlock',
      validators: [
        core.field('type').required().string(),
        core.field('label').required().string(),
      ],
    }],

    #args+: {
    #  [utils.ifNotEmpty(this.depends_on, 'depends_on')]: this.depends_on,
    #  [utils.ifNotNull(this.provider, 'provider')]: this.provider,
    #  [utils.ifNotEmpty(this.lifecycle, 'lifecycle')]: this.lifecycle,
    #  [utils.ifNotNull(this.for_each, 'for_each')]: this.for_each.text,
    #},
  },

  DataBlock: $.EntityBlock + {
    block_type: 'data',
  },

  ResourceBlock: $.EntityBlock + {
    block_type: 'resource',
  },

  ModuleBlock: $.Block + {
    local this = self,

    block_type:: 'module',
    block_render_info+:: {
      key_by: 'label',
    },
    label:: null,
    source: null,
    version: null,

    __validate__+:: [{
      name: 'lang.ModuleBlock',
      validators: [
        core.field('label').required().string(),
        core.field('source').required().string(),
      ],
    }],

    #args+: {
    #  source: this.source,
    #  [utils.ifNotNull(this.version, 'version')]: this.version,
    #},
  },

  OutputBlock: $.Block + {
    local this = self,

    block_type:: 'output',
    block_render_info+:: {
      key_by: 'label',
    },
    label:: null,
    expression: null,
    description: null,
    preconditions: [],
    sensitive: false,
    depends_on: [],  // Array of reference string (e.g. {entity_type}.{label})

    __validate__+:: [{
      name: 'lang.OutputBlock',
      validators: [
        core.field('label').required().string(),
        core.field('expression').required().string(),
      ],
    }],
    __manifest__+:: {
      rename+: {
        expression: 'value',
      },
    },

    #args+: {
    #  value: this.expression,
    #  [utils.ifNotNull(this.description, 'description')]: this.description,
    #  [utils.ifNotEmpty(this.preconditions, 'precondition')]: this.preconditions,
    #  [if this.sensitive then 'sensitive' else null]: true,
    #  [utils.ifNotEmpty(this.depends_on, 'depends_on')]: this.depends_on,
    #},
  },

  ImportBlock: $.Block + {
    local this = self,

    block_type:: 'import',
    to: null,
    id: null,
    provider: null,

    __validate__+:: [{
      name: 'lang.ImportBlock',
      validators: [
        core.field('to').required().string(),
        core.field('id').required().string(),
      ],
    }],

    #args+: {
    #  to: this.to,
    #  id: this.id,
    #  [utils.ifNotNull(this.provider, 'provider')]: this.provider,
    #},
  },

  MovedBlock: $.Block + {
    local this = self,
    block_type:: 'moved',
    from: null,
    to: null,
    provider: null,

    __validate__+:: [{
      name: 'lang.MovedBlock',
      validators: [
        core.field('to').required().string(),
        core.field('from').required().string(),
      ],
    }],

    #args+: {
    #  from: this.from,
    #  to: this.to,
    #},
  },

  ForEach: core.Object + {
    // Raw text representation of an hcl expression. Should evaluate to either
    // a map or a set of strings (for the latter, call hcl `toset()` function).
    // TODO: provide higher level interface
    raw_expression:: null,
    text:: '${%s}' % [self.raw_expression],
  },

  Each: core.Object + terra.ReferenceMixin + {
    is_virtual:: true,
    reference_string:: 'each',
    #attributes: ['key', 'value'],
  },
}