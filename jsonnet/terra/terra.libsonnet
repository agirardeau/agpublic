local core = import 'common/core.libsonnet';
local lang = import 'common/lang.libsonnet';
local utils = import 'common/utils.libsonnet';

{
  Config: core.Object + {
    local this = self,

    // Name should be unique among configs that may reference each other
    name: null,
    terraform_version: '>= 1.9.0',
    providers: [],
    contents: {},
    modules: {},  // TODO - Figure this out more. Should modules go in contents? How to reference resources created by modules?
    backend: null,

    __validate__+:: [{
      name: 'terra.Config',
      validators+: [
        core.field('name').required(),
        core.field('providers').nonEmpty().children(),
        core.field('contents').children(),
      ],
      debug+: ['name'],
    }],

    terraform_block: lang.TerraformBlock + {
      required_version: this.terraform_version,
      required_providers: {
        [p.slug]: {
          source: p.source,
          version: p.version,
        },
        for p in this.providers
      },
      backend: this.backend,
    },
    default_provider_blocks: [p.default_provider_block for p in this.providers],

    #local entities_by_kind = $.entitiesByKind(this.contents),
    local all_entities = $.allEntities(this.contents),
    local blocks_by_type = utils.groupByField(utils.flatten([
      this.terraform_block,
      this.default_provider_blocks,
      std.flatMap(function(e) e.blocks(), all_entities),
      std.objectValues(this.modules),
    ]), 'block_type'),
    local providers_by_slug = {[p.slug]: p for p in this.providers},
    local blocks_by_type_patched = blocks_by_type + {
      provider: [
        pb + providers_by_slug[pb.slug].provider_block_overlay
        for pb in blocks_by_type.provider
      ],
    },

    #output: {
    output: core.Object + {
      [entry.key]: lang.Block.render(entry.value)
      for entry in std.objectKeysValues(blocks_by_type_patched)
    },

    data(relpath='.')::
      $.ExternalConfigData + {
        local res = self,

        label: '%s_external_config' % [this.name],
        backend: this.backend + {
          [utils.fieldNameIfHas(this.backend, 'path')]:
            '%s/%s' % [relpath, this.backend.path],
        },
        #resources: entities_by_kind.resources,
        resources: std.filter(function(e) e.block_type == lang.ResourceBlock.block_type, all_entities),
      },
  },

  Backend: lang.Block + {
    block_type:: 'backend',
    backend_type:: null,
    render_info+:: {
      key_by: 'backend_type',
    },
    __validate__+:: [{
      name: 'lang.BackendBlock',
      validators+: [
        core.field('backend_type').required().string(),
      ],
    }],
  },

  LocalBackend: $.Backend + {
    local this = self,
    backend_type:: 'local',
    path: './terraform.tfstate',
  },

  ExternalConfigData: $.Data + {
    local this = self,

    type: 'terraform_remote_state',
    backend: null,
    resources: [],
    references: {
      [r.label]: $.ExternalResourceReference + {
        external_config_data: this,
        resource: r,
      }
      for r in this.resources
    },

    __validate__+: [{
      name: 'terra.ExternalConfigData',
      validators: [
        core.field('backend').required(),
      ],
    }],

    args+: {
      backend: this.backend.backend_type,
      config: this.backend.args,
    },

    #data(label)::
    #  $.ExternalResourceReference + {
    #    external_config: this,
    #    resource_label: label,
    #  },
  },

  ExternalResourceReference: core.Object + $.ReferenceMixin + {
    local this = self,

    is_virtual: true,
    external_config_data: null,
    resource: null,
    attribute_base_string: 'data.%s.%s.outputs.%s_' % [
      $.ExternalConfigData.type,
      this.external_config_data.label,
      this.resource.label,
    ],
    #attributes: this.resource.attributes,

    __validate__+: [{
      name: 'terra.ExternalResourceReference',
      validators: [
        core.field('external_config_data').required(),
        core.field('resource_label').required(),
      ],
    }],
  },

  Provider: core.Object + {
    local this = self,

    // Args
    slug: null,
    version: null,
    source: 'hashicorp/%s' % [self.slug],
    default_provider: null,
    // Overlay added to each provider block specified for this provider
    provider_block_overlay: {},

    __validate__+: [{
      name: 'terra.Provider',
      validators: [
        core.field('slug').required(),
        core.field('version').required(),
        core.field('default_provider_block').check(function(value)
          if value.alias != null
          then 'Default provider specifies an alias'
          else null
        ),
      ],
    }],
  },

  // Mixin for entities that can be referenced by id in hcl expressions.
  ReferenceMixin: {
    local this = self,

    reference_string:: null,
    attribute_base_string::
      utils.ifNotNull(self.reference_string, '%s%s.' % [
        self.reference_string,
        if this.is_multivalue then '[each.key]' else '',
    ]),
    // Indicates whether this is (not) a reference to an actial resourse
    // defined in a this config. When it is not, the reference shouldn't be
    // included in the `depends_on` argument.
    is_virtual:: false,
    // Indicates whether the reference is to an array of hcl objects (e.g. a
    // for_each resource) 
    is_multivalue:: false,

    __validate__+:: [{
      name: 'terra.ReferenceMixin',
      validators: [
        core.field('attribute_base_string').required(),
      ],
    }],

    attribute(attrname, wrapped=true)::
      if wrapped then '${%s%s}' % [self.attribute_base_string, attrname]
      else '%s%s' % [self.attribute_base_string, attrname],
    attributeUnwrapped(attrname):: self.attribute(attrname, wrapped=false),
    // TODO: remove these, don't check attributes
    #attribute(attrname, checked=false, wrapped=true)::
    #  local root_attr = std.split(attrname, '.')[0];
    #  assert !checked || std.member(self.attributes, root_attr) :
    #    'terra.ReferenceMixin: No attribute `%s`' % [root_attr];
    #  if wrapped then '${%s%s}' % [self.attribute_base_string, attrname]
    #  else '%s%s' % [self.attribute_base_string, attrname],
    #attributeUnwrapped(attrname):: self.attribute(attrname, wrapped=false),
    #attributeUnchecked(attrname):: self.attribute(attrname, checked=false),
    #attributeUncheckedUnwrapped(attrname):: self.attribute(attrname, checked=false, wrapped=false),
    id():: self.attribute('id'),
  },

  // Mixin for nodes that form a nested tree of entities, i.e. entities and
  // bundles. Provides logic for building resource labels from tags of nodes
  // in the tree.
  NestedContentMixin: core.Object + {
    local this = self,

    tag:: null,
    parent_label:: null,
    is_leaf:: true,
    
    __validate__+:: [{
      name: 'terra.NestedContentMixin',
      validators: [
        core.field('label').required(),
        core.check(function(obj)
          if obj.is_leaf && !std.objectHas(this, 'block_type') then 'Leaf node must specify `block_type` property'
          else if !obj.is_leaf && !std.objectHas(this, 'children') then 'Non-leaf node must specify `children` property'
          else null,
        ),
      ],
      debug: ['tag'],
    }],

    label::
      if self.tag == null
      then null
      else if self.parent_label == null || self.parent_label == ''
      then self.tag
      else '%s_%s' % [self.parent_label, self.tag],
  },

  // Mixin for entities (resources and data sources) contained in terraform
  // configs.
  EntityMixin: $.ReferenceMixin + $.NestedContentMixin + {
    local this = self,
    #kind:: null,
    type:: null,
    depends_on: [],  // Array of ReferenceMixin object
    lifecycle: {},
    for_each: null,
    // Use the provider with this reference rather than the default provider
    // for this provider. Reference should be of the form `{SLUG}.{ALIAS}`.
    provider_reference: null,
    filters: [],

    #args: {},
    #block_base: null,
    #self_block: self.block_base + {
    #  type: this.type,
    #  label: this.label,
    #  args+: this.args,
    #  depends_on:
    #    [r.reference_string for r in utils.flatten(this.depends_on) if !r.is_virtual],
    #  provider: this.provider_reference,
    #  lifecycle: this.lifecycle,
    #  for_each: this.for_each,
    #},
    #blocks:: [this],

    // Blocks to be added to the top level config. Blocks required by multiple
    // entities are deduped.
    required_blocks:: [],
    // Convenience method for getting all blocks
    blocks():: [this] + this.required_blocks,
    reference_string:: '%s.%s.%s' % [self.block_type, self.type, self.label],
    is_multivalue:: self.for_each != null,

    __validate__+:: [{
      name: 'terra.Entity',
      validators: [
        #core.field('kind').required(),
        core.field('type').required(),
        #core.field('block_base').required(),
        core.field('depends_on').arrayOf('object'),
        core.field('required_blocks').arrayOf('object'),
      ],
      debug: ['type'],
    }],
    __manifest__+:: {
      rename+: {
        provider_reference: 'provider',
        filters: 'filter',
      },
      overlay+: {
        depends_on: [
          r.reference_string
          for r in utils.flatten(this.depends_on)
          if !r.is_virtual
        ],
      },
    },

    #Kind:: {
    #  DATA: 'data',
    #  RESOURCE: 'resource',
    #},
  },

  Data: lang.DataBlock + $.EntityMixin + {
    #kind:: $.Entity.Kind.DATA,
  },

  Resource: lang.ResourceBlock + $.EntityMixin + {
    local this = self,

    #kind:: $.Entity.Kind.RESOURCE,
    import_id:: null,
    moved_from_label:: null,
    // Attributes to include in the the config outputs.
    // TODO: Move this into terra.Resource
    output_attributes:: ['id'],
    required_blocks+:: (
      if this.import_id != null
      then [lang.ImportBlock + {
        id: this.import_id,
        to: this.reference_string,
      }]
      else []
    ) + (
      if this.moved_from_label != null
      then [lang.MovedBlock + {
        from: '%s.%s' % [this.type, this.moved_from_label],
        to: this.reference_string,
      }]
      else []
    ) + [
      lang.OutputBlock + {
        label: '%s_%s' % [this.label, a],
        expression: this.attribute(a),
      }
      for a in this.output_attributes
      // Outputs don't work (for now) when for_each is set
      if this.for_each == null 
    ],
  },

  // Note: children must inherit from `common_child_opts` to have correct labels
  // (and extra common fields set by subclass templates, like AWS region set by
  // aws.PerRegionBundle)
  Bundle: core.Object + $.NestedContentMixin + {
    local this = self,
    tag:: '',
    common_child_opts:: {
      parent_label: this.label,
    },
    is_leaf:: false,
    children: [],
    #contents():: {
    #  data: utils.flatten([x.contents.data for x in this.children]),
    #  resources: utils.flatten([x.contents.resources for x in this.children]),
    #},

    __validate__+:: [{
      name: 'terra.Bundle',
      validators: [
        core.field('children').children().ignoreNulls(),
      ],
    }],
  },

  Std: {
    call(function_name, args)::
      '${%s(%s)}' % [
        function_name,
        std.join(
          ', ',
          std.map(
            function(x)
              local type = std.type(x);
              if std.member(['number', 'boolean', 'null'], type) then std.toString(x)
              else if type == 'string' then '"%s"' % [x]
              else
                assert false : 'Cannot pass argument of type `%s` to terraform functions' % [type];
                null,
            args,
          ),
        ),
      ],
    cidrsubnet(prefix, newbits, netnum)::
      $.Std.call('cidrsubnet', [prefix, newbits, netnum]),
  },

  allEntities(contents)::
    std.foldl(
      function(res, elem)
        if elem == null then res
        else if elem.is_leaf then res + [elem]
        else res + $.allEntities(elem.children),
      utils.coerceToArray(contents),
      [],
    ),

  #  std.flatMap(
  #    function(e) if e == null then [] else (
  #      if pred(e) then [e] else []
  #    ) + (
  #      assert std.objectHasAll(e, 'kind') : 'Entity is missing required field `kind`';
  #      if e.kind == $.EntityKind.BUNDLE
  #      then $.descendantsDepthFirst(e.children, pred)
  #      else []
  #    ),
  #    utils.coerceToArray(entities)
  #  ),
  
  #allData(entities):: $.descendantsDepthFirst(entities, function(e) e.kind == $.EntityKind.DATA),
  #allResources(entities):: $.descendantsDepthFirst(entities, function(e) e.kind == $.EntityKind.RESOURCE),
}
