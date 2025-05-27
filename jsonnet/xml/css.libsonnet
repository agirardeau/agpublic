// Resources:
//  Syntax reference: https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_syntax/Syntax
//  A reasonable AST: https://github.com/csstree/csstree/blob/master/docs/ast.md
local core = import 'core/core.libsonnet';
local math2d = import 'core/math2d.libsonnet';
local utils = import 'core/utils.libsonnet';

// Issue~
// Sometimes a Node wants to defer to a child node to determine what
// whitespace or delimiters to include around it. For example, Declaration
// would like to defer to ListValue to decide whether to start a new (indented)
// line before the list value.
//
// One option would be to have the render() methods return some context, like
// whether they rendered multiple lines or just one:
//
//  local RenderResult = {
//    is_multiline: false,
//    start_new_line: false,
//    lines: [],
//    text: '',
//  };
//
// Another option is to add an `is_inline` or `is_multiline` property to all
// nodes.
//
// For now, we've done none of those, the consequence being that there's an
// extra trailing whitespace for declarations whose values are indented lists:
//
//  @foo {
//    bar:  /* extra trailing space on this line */
//      baz(qux),
//      garply(grundle);
//  }
//

local checkIsNode(node) =
  if utils.isPrimitive(node) then
    null
  else if !std.isObject(node) then
    error 'Node must be an object or primitive, found type `%s`' % [std.type(node)]
  else if !std.objectHasAll(node, 'render') then
    error 'Node must have a render() method'
  else if !std.isFunction(node.render) then
    error 'Node\'s render() property must be a function, found type `%s`' % [std.type(node.render)]
  else
    null;

#local checkNodes(nodes) =
#  if std.isArray(nodes) then
#
#  else
#    checkSingleNode()

local RENDER_OPTIONS = {
  base_indent: '',
  indent: '  ',
};

// Renders a node. Accepts either a node object or a primitive.
local renderNode(node, options={}) =
  local opts = RENDER_OPTIONS + options;
  local check = checkIsNode(node);
  if check != null then
    error 'css.render(): ' + check
  else if std.isString(node) then
    '\'%s\'' % std.toString(node)
  else if utils.isPrimitive(node) then
    std.toString(node)
  else
    node.render(opts);

// Renders each node in a array of nodes. If a single node is provided instead
// of a list, returns a singleton array containing that node rendered. 
local renderNodes(nodes, options={}) =
  local opts = RENDER_OPTIONS + options;
  if nodes == null then
    []
  else if !std.isArray(nodes) then
    [renderNode(nodes, opts)]
  else
    [renderNode(x, opts) for x in nodes];

{
  pxToIn(px): px / 96,
  inToPx(inches):: inches * 96,

  render(rules, options={}, current_indent='')::
    local opts = RENDER_OPTIONS + options;
    std.join('\n\n', [
      opts.base_indent + rule.render(opts)
      for rule in utils.asArray(rules)
    ]),

  Node: core.Object + {
    render:: null,
    __validate__+:: [{
      name: 'css.Node',
      validators: [
        core.field('render').required().fn(),
      ],
    }],
    // TODO - try using `transform` to make css nodes always serialize to
    // strings to see if that simplifies code
    // Might want to pass manifest options to transform() as optional second
    // argument so that stuff like indent can be respected
    //__manifest__+:: {
    //  transform(obj):: renderNode(obj),
    //},
  },

  Statement: $.Node + {
    local this = self,
    prelude_contents: null, 
    block_contents: null, // Array of Rule, AtRule, or Declaration
    always_render_block: false, // If true, render an empty block if block contents 
    __validate__+:: [{
      name: 'css.Statement',
      validators: [
        core.field('prelude_contents').maybeArray().checkElements(checkIsNode).children(),
        core.field('block_contents').maybeArray().checkElements(checkIsNode).children(),
      ],
    }],
    render(options={})::
      local opts = RENDER_OPTIONS + options;
      local child_opts = opts + {
        base_indent: opts.base_indent + opts.indent,
      };
      // prelude_contents should not contain any statements or declarations
      // (aka all prelude nodes are inline), so doesn't matter if we pass
      // updated opts, old opts, or no opts
      local prelude_contents_rendered = renderNodes(this.prelude_contents, opts);
      local block_contents_rendered = renderNodes(this.block_contents, child_opts);
      if std.length(block_contents_rendered) == 0 then
        std.join(' ', prelude_contents_rendered) + ';'
      else
        std.join('\n', utils.flatten([
          std.join(' ', prelude_contents_rendered) + ' {',
          [
            child_opts.base_indent + rendered
            for rendered in block_contents_rendered
          ],
          '}',
        ])),
  },

  Rule: $.Statement + {
    // TODO
    selectors: null,
    declarations: null,
    prelude_contents:: self.selectors,
    block_contents:: self.declarations,
    __validate__+:: [{
      name: 'css.Rule',
      validators: [
        core.field('selectors').maybeArray().checkElements(checkIsNode).children(),
        core.field('declarations').maybeArray().checkElements(checkIsNode).children(),
      ],
    }],
  },

  AtRule: $.Statement + {
    local this = self,
    rule_name: null,
    prelude_contents: [$.raw('@%s' % [this.rule_name])], 
    __validate__+:: [{
      name: 'css.AtRule',
      validators: [
        core.field('rule_name').required().string(),
      ],
    }],
  },

  // https://developer.mozilla.org/en-US/docs/Web/CSS/@font-face
  FontFace: $.AtRule + {
    local this = self,
    rule_name: 'font-face',
    font_family_name: null,
    sources: null,
    __validate__+:: [{
      name: 'css.FontFace',
      validators: [
        core.field('font_family_name').required().string(),
        core.field('sources').maybeArray().checkElements(checkIsNode).children(),
      ],
    }],
    block_contents:: [
      $.Declaration + {
        property: 'font-family',
        value: this.font_family_name,
      },
      $.Declaration + {
        property: 'src',
        value: $.ListValue + {
          entries: [$.fns.loc(this.font_family_name)] + utils.asArray(this.sources),
          delimiter: ',',
          should_indent: true,
        },
      },
    ],
  },

  Import: $.AtRule + {
    local this = self,
    rule_name: 'import',
    url: null,
    __validate__+:: [{
      name: 'css.FontFace',
      validators: [
        core.field('url').required().string(),
      ],
    }],
    prelude_contents+:: [
      $.fns.url(this.url),
    ],
  },

  Declaration: $.Node + {
    local this = self,
    property: null,
    value: null,
    important: false,
    __validate__+:: [{
      name: 'css.Declaration',
      validators: [
        core.field('property').required().string(),
        core.field('value').required().check(checkIsNode).child(),
        core.field('important').required().boolean(),
      ],
    }],
    render(options={})::
      local opts = RENDER_OPTIONS + options;
      local new_opts = opts + {
        base_indent: opts.base_indent + opts.indent,
      }; 
      '%s: %s%s;' % [
        this.property,
        renderNode(this.value, new_opts),
        if this.important then ' !important' else '',
      ],
  },

  declarations(obj, important=false):: [
    $.Declaration + {
      property: utils.snakeCaseToKebabCase(entry.key),
      value: entry.value,
      important: important,
    }
    for entry in std.objectKeysValues(obj)
    if entry.value != null
  ],

  ListValue: $.Node + {
    local this = self,
    entries: null,
    delimiter: ' ',
    final_delimiter: '',
    should_indent: false,
    __validate__+:: [{
      name: 'css.ListValue',
      validators: [
        core.field('entries').required().maybeArray().checkElements(checkIsNode).children(),
        core.field('delimiter').required().string(),
        core.field('final_delimiter').required().string(),
        core.field('should_indent').required().boolean(),
      ],
    }],
    render(options={})::
      local opts = RENDER_OPTIONS + options;
      local new_opts = opts + { base_indent: opts.base_indent + opts.indent };
      local rendered = renderNodes(this.entries, new_opts);
      if this.should_indent then
        '\n%s%s%s' % [
          opts.base_indent,
          std.join(
            '%s\n%s' % [this.delimiter, opts.base_indent],
            rendered,
          ),
          this.final_delimiter,
        ]
      else
        std.join(this.delimiter, rendered) + this.final_delimiter,
  },

  list(entries, delimiter=' ', final_delimiter='', should_indent=false):: $.ListValue + {
    entries: entries,
    delimiter: delimiter,
    final_delimiter: final_delimiter,
    should_indent: should_indent,
  },

  Call: $.Node + {
    local this = self,
    function_name:: null,
    args:: null,
    __validate__+:: [{
      name: 'css.Call',
      validators: [
        core.field('function_name').required().string(),
        core.field('args').maybeArray().checkElements(checkIsNode).children(),
      ],
    }],
    #render(_):: '%s(%s)' % [this.function_name, std.join(', ', this.args)],
    #render(_):: '%s(%s)' % [this.function_name, std.join(', ', utils.asArray(this.args))],
    #render(_):: '%s(%s)' % [this.function_name, this.args],
    render(_={}):: '%s(%s)' % [this.function_name, std.join(', ', renderNodes(this.args))],
  },
  
  call(fn, args=[]):: $.Call + {
    function_name: fn,
    args: args,
  },

  fns:: {
    loc(args=[]): $.call('local', args),
  } + {
    [x]: function(args=[]) $.call(x, args)
    for x in [
      'url',
      'format',
      'tech',
    ]
  },

  Enum: $.Node + {
    name:: null,
    __validate__+:: [{
      name: 'css.Enum',
      validators: [
        core.field('name').required().string(),
      ],
    }],
    render(_={}):: self.name,
  },

  enum(name):: $.Enum + {
    name: name,
  },

  enums: {
    SERIF: $.enum('serif'),
  },

  Raw: $.Node + {
    raw:: null,
    __validate__+:: [{
      name: 'css.Raw',
      validators: [
        core.field('raw').required().string(),
      ],
    }],
    render(_={}):: self.raw,
  },

  raw(raw):: $.Raw + {
    raw: raw,
  },

  Transform:: $.Node + {
    local this = self,
    name: null,
    args: null,
    __validate__+:: [{
      name: 'css.Transform',
      validators: [
        core.field('name').required().string(),
        core.field('args').required().array(),
      ],
    }],

    #local maybePx(x) = if std.isNumber(x) && x != 0 then '%spx' % [x] else std.toString(x),
    local maybePx(x) = std.toString(x),
    render(_={}):: '%s(%s)' % [
      this.name,
      std.join(', ', [maybePx(x) for x in this.args]),
    ],

    renderAll(transforms):: std.join(' ', [x.render() for x in transforms]),
  },

  // Accepts xy coordinates in any form accepted by math2d.vec()
  translate(dx, dy=null):: $.Transform + {
    local vec = math2d.vec(dx, dy),
    name: 'translate',
    args: [vec.x, vec.y],
  },

  #Hsl: core.Object + {
  #  local this = self
  #  h: null,
  #  s: null,
  #  l: null,
  #  a: 0,
  #  __manifest__+:: {
  #    transform(obj):: 'hsla(%s, %s, %s, %s)' % [h, s, l, a]
  #  },
  #},

  color: {
    rgb(r, g, b):: 'rgb(%s, %s, %s)' % [r, g, b],
    rgba(r, g, b, a):: 'rgba(%s, %s, %s, %s)' % [r, g, b, a],
    hsl(h, s, l):: 'hsl(%s, %s, %s)' % [h, s, l],
    hsla(h, s, l, a):: 'hsla(%s, %s, %s, %s)' % [h, s, l, a],
  },
}