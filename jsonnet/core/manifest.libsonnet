local core = import "./core.libsonnet";
local utils = import "./utils.libsonnet";

{
  local identity(x) = x,

  local DEFAULT_MANIFEST_CONFIG = {
    // Object to overlay onto the 
    overlay: {},
    // Map where keys are original field names and values are renamed field
    // names as strings.
    rename: {},
    // Whether to include empty-ish values in output.
    prune_null: false,
    prune_empty_list: false,
    prune_empty_object: false,
    prune_false: false,
    // Additional transform to apply to the object after rename, overlay, and
    // mutator transforms have been applied. Should be a function accepting one
    // argument (the partially transformed value). May return any type.
    transform:: identity, 

    // manifest parameters should be declared with `+:` syntax, this field
    // allows us to detect if they were not and emit a warning.
    __inherits_manifest_config__:: true,
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

  local transformInternal(value, options) = 
    local opts = TRANSFORM_OPTIONS + options;
    if !std.isObject(value) then 
      error('manifest.transform() expected an object, got %s' % [std.type(value)])
    else
      local manifest_config = utils.get(value, '__manifest__', DEFAULT_MANIFEST_CONFIG);
      local debugged_value = utils.maybeLogged(
        value,
        !std.objectHasAll(manifest_config, '__inherits_manifest_config__'),
        'Warning: value with `__manifest__` property that doesn\'t inherit from base. Likely indicates `__manifest__ ` field that doesn\'t use object merge syntax (`+:`)');
      local overlaid = utils.overlay(debugged_value, manifest_config.overlay);
      local mutated = {
        [$.applyMutators(
          // If the field name is present in manifest_config.rename, use the
          // value stored there, otherwise use the key unchanged
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
      };
      manifest_config.transform(mutated),

  local manifestInternal(value, options, is_recursion=false) =
    local opts = if is_recursion then options else MANIFEST_OPTIONS + options;
    local transformed =
      if std.isObject(value) then
        transformInternal(value, opts)
      else
        value;
    local manifested_but_not_serialized =
      if std.isObject(transformed) then
        {
          [entry.key]: manifestInternal(entry.value, opts, true)
          for entry in std.objectKeysValues(transformed)
        }
      else if std.isArray(transformed) then
        [
          manifestInternal(x, opts, true)
          for x in $.applyMutators(transformed, opts.value_mutators)
        ]
      else $.applyMutators(transformed, opts.value_mutators);
    (if is_recursion then identity else opts.serializer)(
      utils.maybeLogged(manifested_but_not_serialized, opts.should_log, opts.trace_label),
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

  // Applies transformations in the `__manifest__` property on both the provided
  // value and its children, then serializes to a string
  manifest(value, options={})::
    manifestInternal(value, options),

  // Applies transformations in the `__manifest__` property on both the provided
  // value and its children, then serializes to a string. Logs to stdout.
  manifestLogged(value, label, options={})::
    manifestInternal(value, {
      should_log: true,
      trace_label: label,
    } + options),

  // Applies transformations in the `__manifest__` property of the provided
  // value. Does not recursively transform children or serialize to a string.
  transform(value, options={}):: transformInternal(value, options),

  // Value calculated from other values. Allows mutators to apply
  // intermediate results.
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

  // Is this a bad idea? it seems like a recipe for messing up and getting a confusing error message about
  // wrong number of template terms. Maybe it would be better to use a new class instead of reusing TemplatedValue.
  templateEach(template, delimiter, items, terms_from_item=function(x) [x]):: $.TemplatedValue + {
    local terms = utils.flatten([terms_from_item(x) for x in items]),
    terms: terms,
    template: std.join(delimiter, std.repeat([template], std.length(items))),
    #terms: utils.logged(terms, 'TERMS'),
    #template: utils.logged(std.join(delimiter, std.repeat([template], std.length(items))), 'TEMPLATE'),
  },

  #Mutator: core.Object + {
  #  types: null,
  #  apply(value): if std.contains(self.types, std.type(value)) then self.mutate(value) else value,
  #  mutate(value): error 'manifest.Mutator: mutate() not implemented',
  #},

  mutators: {
    // Converts numbers into *string representations* containing at most the
    // specified precision
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