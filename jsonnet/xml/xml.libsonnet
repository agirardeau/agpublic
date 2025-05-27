local core = import 'core/core.libsonnet';
local manifest = import 'core/manifest.libsonnet';
local utils = import 'core/utils.libsonnet';

local MANIFEST_OPTIONS = {
  base_indent: '',
  indent: '  ',
  should_log: false,
  trace_label: '',
  float_precision: null,
  key_mutators: [],
  value_mutators+: utils.singletonArrayIf(
    self.float_precision != null,
    manifest.mutators.round(self.float_precision),
  ),
};

local manifestInternal(elem, options, is_recursion=false) = 
  local opts = MANIFEST_OPTIONS + options;
  local res =
    if !(std.isObject(elem) || utils.isPrimitive(elem)) then
      error 'Expected object or primitive, got %s'
            % std.type(elem)
    else
      local maybe_newline = if opts.indent != '' then '\n' else '';
      local attrs = std.join('', [
        ' %s="%s"' % [entry.key, entry.value]
        for entry in std.objectKeysValues(manifest.transform(elem, opts))
      ]);
      if manifest.isMutatable(elem) then
        '%s%s' % [opts.base_indent, manifest.applyMutators(elem, opts.value_mutators)]
      else if std.isObject(elem) then
        local mutated_tag = manifest.applyMutators(elem.tag, opts.key_mutators);
        if std.length(elem.has) == 1 && utils.isPrimitive(elem.has[0]) then
          '%s<%s%s>%s</%s>' % [
            opts.base_indent,
            mutated_tag,
            attrs,
            elem.has[0],
            mutated_tag,
          ]
        else if std.length(elem.has) > 0 then
          std.join(maybe_newline, [
            '%s<%s%s>' % [opts.base_indent, mutated_tag, attrs],
            std.join(maybe_newline, [
              manifestInternal(x, opts + { base_indent: opts.base_indent + opts.indent }, true)
              for x in elem.has
            ]),
            '%s</%s>' % [opts.base_indent, mutated_tag],
          ])
        else
          '%s<%s%s></%s>' % [
            opts.base_indent,
            mutated_tag,
            attrs,
            mutated_tag,
          ]
      else
        error 'Unexpected type %s' % std.type(elem);
  utils.maybeLogged(res, opts.should_log && !is_recursion, opts.trace_label);

{
  Element: core.Object + {
    local this = self,

    tag:: null,
    has:: [],

    __validate__+:: [{
      name: 'xml.Element',
      validators: [
        core.field('tag').required().string(),
        core.field('has').required().array().children(),
      ],
      debug+: ['tag'],
    }],

    xmlMini(options={}):: self.xml({
      indent: '',
    } + options),

    xmlMiniLogged(label, options={}):: self.xmlMini({
      should_log: true,
      trace_label: label,
    } + options),

    xmlPretty(options={}):: self.xml({
      indent: '  ',
    } + options),

    xmlPrettyLogged(label, options={}):: self.xmlPretty({
      should_log: true,
      trace_label: label,
    } + options),

    xml(options={}):: $.manifest(self, options),
  },

  StyleMixin: {
    local this = self,

    style:: {},
    __validate__+:: [{
      name: 'xml.StyleMixin',
      validators: [
        core.field('style').object(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        [if std.length(this.style) != 0 then 'style' else null]:  manifest.template(
          std.join(';', [
            utils.snakeCaseToKebabCase(k) + ':%s'
            for k in std.objectFields(this.style)
          ]),
          std.objectValues(this.style),
        ),
      },
    },
  },

  StyleElement: $.Element + $.StyleMixin,

  manifest(elem, options={})::
    manifestInternal(elem, options),

  manifestLogged(elem, label, opts={})::
    manifestInternal(elem, {
      should_log: true,
      trace_label: label,
    }),
}