local utils = import "./utils.libsonnet";

local DEFAULT_MANIFEST_CONFIG = {
  rename: {},
  overlay: {},
  prune_null: false,
  prune_empty_list: false,
  prune_empty_object: false,
  prune_false: false,
};

local identity(x) = x;

local manifestInternal(value, fn, should_log, trace_label='') =
  local transformed = 
    if std.type(value) == 'object' then 
      local is_manifest_incomplete =
        std.objectHasAll(value, '__manifest__')
        && (std.length(utils.get(value, '__manifest__', {}))
          < std.length(DEFAULT_MANIFEST_CONFIG));
      local debugged_value = utils.maybeLogged(
        value, is_manifest_incomplete, 'VALUE WITH PARTIAL __MANIFEST__!');
      local manifest_config = utils.get(debugged_value, '__manifest__', DEFAULT_MANIFEST_CONFIG);
      #local overlaid = value + manifest_config.overlay;
      local overlaid = utils.overlay(value, manifest_config.overlay);
      {
        // If the field name is present in manifest_config.rename, use the
        // value stored there, otherwise use the key unchanged
        [utils.get(manifest_config.rename, entry.key, entry.key)]:
          manifestInternal(overlaid[entry.key], identity, false)
        for entry in std.objectKeysValues(overlaid)
        if !(
          (entry.value == null && manifest_config.prune_null)
          || (entry.value == [] && manifest_config.prune_empty_list)
          || (entry.value == {} && manifest_config.prune_empty_object)
          || (entry.value == false && manifest_config.prune_false)
        )
      }
    else if std.type(value) == 'array' then
      std.map(function(x) manifestInternal(x, identity, false), value)
    else value;
  fn(
    utils.maybeLogged(transformed, should_log, trace_label),
  );

{
  Manifest: {
    local this = self,

    __manifest__:: DEFAULT_MANIFEST_CONFIG,

    jsonMini()::
      $.manifest(
        this,
        function(x) std.manifestJsonEx(x, '', '', ':'),
      ),

    jsonMiniLogged(label)::
      $.manifestLogged(
        this,
        function(x) std.manifestJsonEx(x, '', '', ':'),
        label,
      ),

    jsonPretty()::
      $.manifest(
        this,
        function(x) std.manifestJsonEx(x, '  '),
      ),

    jsonPrettyLogged(label)::
      $.manifestLogged(
        this,
        function(x) std.manifestJsonEx(x, '  '),
        label,
      ),

    jsonEx(indent='  ', newline='\n', key_val_sep=': ')::
      $.manifest(
        this,
        function(x) std.manifestJsonEx(x, indent, newline, key_val_sep),
      ),

    jsonExLogged(label, indent='  ', newline='\n', key_val_sep=': ')::
      $.manifestLogged(
        this,
        function(x) std.manifestJsonEx(x, indent, newline, key_val_sep),
        label,
      ),
  },

  manifest(value, fn=function(x) std.manifestJsonEx(x, '  '))::
    manifestInternal(value, fn, false, ''),

  manifestLogged(value, fn=function(x) std.manifestJsonEx(x, '  '), trace_log='')::
    manifestInternal(value, fn, true, trace_log),

  #// If trace_label is provided, the value will be logged to output with the provided
  #// label using std.trace()
  #manifest(value, fn=function(x) std.manifestJsonEx(x, '  '), trace_label='')::
  #  local transformed = 
  #  #fn(
  #    if std.type(value) == 'object' then 
  #    #if std.type(utils.logged(value, 'VALUE PASSED TO MANIFEST')) == 'object' then 
  #      local is_manifest_incomplete =
  #        std.objectHasAll(value, '__manifest__')
  #        && (std.length(utils.get(value, '__manifest__', {}))
  #          < std.length(DEFAULT_MANIFEST_CONFIG));
  #      local debugged_value = utils.maybeLogged(
  #        value, is_manifest_incomplete, 'VALUE WITH PARTIAL __MANIFEST__!');
  #      #local manifest_config = DEFAULT_MANIFEST_CONFIG + utils.get(debugged_value, '__manifest__', {});
  #      local manifest_config = utils.get(debugged_value, '__manifest__', DEFAULT_MANIFEST_CONFIG);
  #      local overlaid = value + manifest_config.overlay;
  #      {
  #        # If the field name is present in manifest_config.rename, use the
  #        # value stored there, otherwise use the key unchanged
  #        [utils.get(manifest_config.rename, entry.key, entry.key)]:
  #          $.manifest(overlaid[entry.key], identity)
  #        for entry in std.objectKeysValues(overlaid)
  #        if !(
  #          (entry.value == null && manifest_config.prune_null)
  #          || (entry.value == [] && manifest_config.prune_empty_list)
  #          || (entry.value == {} && manifest_config.prune_empty_object)
  #          || (entry.value == false && manifest_config.prune_false)
  #        )
  #      }
  #    else if std.type(value) == 'array' then
  #      std.map(function(x) $.manifest(x, identity), value)
  #    #else value,
  #    else value;
  #  #),
  #  fn(
  #    #utils.maybeLogged(transformed, std.length(trace_label) > 0, trace_label),
  #    #utils.logged(transformed, trace_label),
  #    utils.logged(transformed, 'TRANSFORMEDDDDDDDDDD'),
  #    #transformed,
  #  ),
}