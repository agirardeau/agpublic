local core = import "./core.libsonnet";
local utils = import "./utils.libsonnet";

{
  local DEFAULT_MANIFEST_CONFIG = {
    rename: {},
    overlay: {},
    prune_null: false,
    prune_empty_list: false,
    prune_empty_object: false,
    prune_false: false,
  },

  local TRANSFORM_OPTIONS = {
    float_precision: null,
    key_mutators: [],
    value_mutators+: utils.singletonArrayIf(
      self.float_precision != null,
      $.mutators.round(self.float_precision),
    ),
  },

  local MANIFEST_OPTIONS = TRANSFORM_OPTIONS + {
    serializer: function(x) std.manifestJsonEx(x, '  '),
    should_log: false,
    trace_label: '',
  },

  local identity(x) = x,

  local transformInternal(value, options) = 
    local opts = TRANSFORM_OPTIONS + options;
    if !std.isObject(value) then 
      error('manifest.transform() expected an object, got %s' % [std.type(value)])
    else
      local is_manifest_incomplete =
        std.objectHasAll(value, '__manifest__')
        && (std.length(utils.get(value, '__manifest__', {}))
          < std.length(DEFAULT_MANIFEST_CONFIG));
      local debugged_value = utils.maybeLogged(
        value, is_manifest_incomplete, 'VALUE WITH PARTIAL __MANIFEST__!');
      local manifest_config = utils.get(debugged_value, '__manifest__', DEFAULT_MANIFEST_CONFIG);
      local overlaid = utils.overlay(value, manifest_config.overlay);
      {
        // If the field name is present in manifest_config.rename, use the
        // value stored there, otherwise use the key unchanged
        [$.applyMutators(
          utils.get(manifest_config.rename, entry.key, entry.key),
          opts.key_mutators,
        )]: $.applyMutators(overlaid[entry.key], opts.value_mutators)
        for entry in std.objectKeysValues(overlaid)
        if !(
          (entry.value == null && manifest_config.prune_null)
          || (entry.value == [] && manifest_config.prune_empty_list)
          || (entry.value == {} && manifest_config.prune_empty_object)
          || (entry.value == false && manifest_config.prune_false)
        )
      },

  local manifestInternal(value, options, is_recursion=false) =
    local opts = if is_recursion then options else MANIFEST_OPTIONS + options;
    local transformed =
      if std.type(value) == 'object' then
        {
          [entry.key]: manifestInternal(entry.value, opts, true)
          for entry in std.objectKeysValues(transformInternal(value, opts))
        }
      else if std.type(value) == 'array' then
        [
          manifestInternal(x, opts, true)
          for x in $.applyMutators(value, opts.value_mutators)
        ]
      else $.applyMutators(value, opts.value_mutators);
    (if is_recursion then identity else opts.serializer)(
      utils.maybeLogged(transformed, opts.should_log, opts.trace_label),
    ),

  Manifest: {
    local this = self,

    __manifest__:: DEFAULT_MANIFEST_CONFIG,

    jsonMini(options={})::
      $.manifest(this, {
        serializer: function(x) std.manifestJsonEx(x, '', '', ':'),
      } + options),

    jsonMiniLogged(label, options={})::
      $.manifestLogged(this, label, {
        serializer: function(x) std.manifestJsonEx(x, '', '', ':'),
      } + options),

    jsonPretty(options={})::
      $.manifest(this, options),

    jsonPrettyLogged(label, options={})::
      $.manifestLogged(this, label, options),

    jsonEx(indent='  ', newline='\n', key_val_sep=': ', options={})::
      $.manifest(this, {
        serializer: function(x) std.manifestJsonEx(x, indent, newline, key_val_sep),
      } + options),

    jsonExLogged(label, indent='  ', newline='\n', key_val_sep=': ', options={})::
      $.manifestLogged(this, label, {
        serializer: function(x) std.manifestJsonEx(x, indent, newline, key_val_sep),
      } + options),
  },

  manifest(value, options={})::
    manifestInternal(value, options),
    #manifestInternal(value, utils.logged(options, 'OPTIONS')),

  manifestLogged(value, label, options={})::
    manifestInternal(value, {
      should_log: true,
      trace_label: label,
    } + options),

  transform(value, options={}):: transformInternal(value, options),

  // Value calculated from other values, used to apply mutators to intermediate
  // results
  CalculatedValue: core.Object + {
    local this = self,

    terms: null,
    mutate_terms: true,
    mutate_result: true,

    render():: error 'manifest.CalculatedValue: render() not implemented',

    mutate(value_mutators)::
      local rendered = (this + {
        terms: if !this.mutate_terms then this.terms else [
          utils.applyAll(term, value_mutators)
          for term in this.terms
        ]
      }).render();
      if !this.mutate_result
      then rendered
      else utils.applyAll(rendered, value_mutators),

    __validate__+:: [{
      name: 'manifest.CalculatedValue',
      validators: [
        core.field('terms').required().array(),
      ],
    }],
    __manifest__+:: {
      is_calculated_value: true,
    },
  },

  isCalculatedValue(value)::
    std.type(value) == 'object' && utils.get(value, ['__manifest__', 'is_calculated_value'], false),

  isMutatable(value)::
    utils.isPrimitive(value) || $.isCalculatedValue(value),

  // Calculated value based on string templating
  TemplatedValue: $.CalculatedValue + {
    template: null,

    __validate__+:: [{
      name: 'manifest.TemplatedValue',
      validators: [
        core.field('template').required().string(),
      ],
    }],

    render(): self.template % self.terms,
  },

  template(template, terms):: $.TemplatedValue + {
    terms: terms,
    template: template,
  },

  #Mutator: core.Object + {
  #  types: null,
  #  apply(value): if std.contains(self.types, std.type(value)) then self.mutate(value) else value,
  #  mutate(value): error 'manifest.Mutator: mutate() not implemented',
  #},

  mutators: {
    round(digits):: function(x)
      if std.isNumber(x)
      then
        local long_form = ('%.' + std.toString(digits) + 'f') % [x];
        local parts = std.split(long_form, '.');
        local decimal_part_trimmed = if std.length(parts) == 2 then std.rstripChars(parts[1], '0.') else '';
        if decimal_part_trimmed != '' then '%s.%s' % [parts[0], decimal_part_trimmed] else parts[0]
      else x,
  },

  applyMutators(value, value_mutators)::
    if $.isCalculatedValue(value) then
      value.mutate(value_mutators)
    else if utils.isPrimitive(value) then
      utils.applyAll(value, value_mutators)
    else
      value,
}