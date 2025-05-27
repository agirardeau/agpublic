local core = import 'core/core.libsonnet';
local manifest = import 'core/manifest.libsonnet';
local math2d = import 'core/math2d.libsonnet';
local utils = import 'core/utils.libsonnet';

local css = import './css.libsonnet';
local mathml = import './mathml.libsonnet';
local xml = import './xml.libsonnet';

local boolAsInt(bool) = if bool then 1 else 0;

{
  VerticalAlign: {
    TOP: 'top',
    CENTER: 'center',
    BOTTOM: 'bottom',
  },

  HorizontalAlign: {
    LEFT: 'left',
    CENTER: 'center',
    RIGHT: 'right',
  },

  Element: xml.StyleElement + {
    local this = self,

    transforms:: [],
    xml(options={}):: super.xml({
      snake_to_kebab_case: true,
      key_mutators+: utils.singletonArrayIf(self.snake_to_kebab_case, utils.snakeCaseToKebabCase),
    } + options),

    __validate__+:: [{
      name: 'svg.Element',
      validators: [
        core.field('transforms').arrayOfObject().children(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        transform: utils.ifNotEmpty(this.transforms, css.Transform.renderAll(this.transforms)),
      },
    },

  },

  Svg: $.Element + {
    local this = self,
    tag:: 'svg',
    is_inline:: false,
    xmlns: if self.is_inline then null else 'http://www.w3.org/2000/svg',
    size:: null,
    location:: null,
    origin:: $.Svg.Origin.TOP_LEFT,
    viewBox: 
      if self.origin == $.Svg.Origin.TOP_CENTER then
        manifest.template('%s 0 %s %s', [-self.size.x/2, self.size.x, self.size.y])
      else if self.origin == $.Svg.Origin.LEFT_CENTER then
        manifest.template('0 %s %s %s', [-self.size.y/2, self.size.x, self.size.y])
      else if self.origin == $.Svg.Origin.CENTER then
        manifest.template('%s %s %s %s', [-self.size.x/2, -self.size.y/2, self.size.x, self.size.y])
      else
        manifest.template('0 0 %s %s', [self.size.x, self.size.y]),

    // Array of css at-rules
    style_rules:: [],
    has+:: utils.singletonArrayIf(
      std.length(this.style_rules) > 0,
      $.Element + {
        tag:: 'style',
        has:: [
          css.render(this.style_rules),
        ],
      },
    ),

    __validate__+:: [{
      name: 'svg.Svg',
      validators: [
        core.field('size').required().object(),
        core.field('location').object(),
        core.field('origin').string(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        width: this.size.x,
        height: this.size.y,
        x: utils.elseNull(this.location != null, this.location.x),
        y: utils.elseNull(this.location != null, this.location.y),
      },
    },

    Origin:: {
      TOP_LEFT: 'top-left',
      TOP_CENTER: 'top-center',
      LEFT_CENTER: 'left-center',
      CENTER: 'center',
    },
  },

  ForeignObject: $.Element + {
    local this = self,
    tag:: 'foreignObject',
    size:: null,
    location:: null,
    __validate__+:: [{
      name: 'svg.ForeignObject',
      validators: [
        core.field('size').required().object(),
        core.field('location').required().object(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        width: this.size.x,
        height: this.size.y,
        #x: this.location.x,
        #y: this.location.y,
        x: this.location.x - this.width/2,
        y: this.location.y - this.height/2,
      },
    },
  },

  MathML: $.ForeignObject + {
    local this = self,
    content:: null,
    math:: mathml.math(self.content),
    div:: xml.StyleElement + {
      tag:: 'div',
      xmlns: 'http://www.w3.org/1999/xhtml',
      has:: [this.math],
      style+:: {
        display: 'flex',
        justify_content: 'center',
        align_items: 'center',
        height: '%spx' % [this.height],
        width: '%spx' % [this.width],
        box_sizing: 'border-box',
      },
    },
    has:: [this.div],
  },

  Group: $.Element + {
    tag:: 'g',
  },

  Text: $.Element + {
    local this = self,

    tag:: 'text',
    content:: null,
    location:: null,
    text_length: null,

    has+:: utils.asArray(this.content),

    __validate__+:: [{
      name: 'svg.Text',
      validators: [
        core.field('content').required(),
        core.field('location').required().object(),
      ],
    }],
    __manifest__+:: {
      rename+: {
        text_length: 'textLength',
      },
      overlay+: {
        x: this.location.x,
        y: this.location.y,
      },
    },
  },

  text(content, location):: $.Text + {
    content:: content,
    location:: math2d.vec(location),
  },

  #WrappedTextMixin: {
  #  style+:: {
  #    white_space: 'pre-line',
  #  },
  #},

  // This centers text around the xy coordinates of the text element
  CenteredTextMixin: {
    dominant_baseline: 'middle',
    text_anchor: 'middle',
  },
  // Convenience template for a rect containing text
  TextBox: $.Group + {
    local this = self,

    size:: null,
    location:: null,
    text_content:: null,
    vertical_align:: 'center',
    horizontal_align:: 'center',
    mx:: 0,
    my:: 0,

    rect:: $.Rect + {
      size:: this.size,
      location:: this.location,
    },

    text:: $.Text + {
      location:: math2d.vec({
        x:
          if this.horizontal_align == $.HorizontalAlign.LEFT then
            this.location.x + this.mx
          else if this.horizontal_align == $.HorizontalAlign.CENTER then
            this.location.x + this.size.x / 2
          else
            this.location.x + this.size.x - this.mx,
        y:
          if this.vertical_align == $.VerticalAlign.TOP then
            this.location.y + this.my
          else if this.vertical_align == $.VerticalAlign.CENTER then
            this.location.y + this.size.y / 2
          else
            this.location.y + this.size.y - this.my,
      }),
      content:: utils.ifNull(this.text_content, ''),
      width:: this.size.x,
      style+:: {
        // Not clear if this should always be here
        white_space: 'pre-line',
      },
      text_length: this.size.x - (2 * this.mx),
      text_anchor:
        if this.horizontal_align == $.HorizontalAlign.LEFT then
          'start'
        else if this.horizontal_align == $.HorizontalAlign.CENTER then
          'middle'
        else
          'end',
      dominant_baseline:
        if this.vertical_align == $.VerticalAlign.TOP then
          'hanging'
        else if this.vertical_align == $.VerticalAlign.CENTER then
          'central'
          #'middle'
        else
          // This places tails like in the english lowercase "g" below the line
          // unfortunately, but there aren't better options
          'text-top',
    },

    has:: [
      this.rect,
      this.text,
    ],

    __validate__+:: [{
      name: 'svg.TextBox',
      validators: [
        core.field('size').required().object(),
        core.field('location').required().object(),
        core.field('horizontal_align').required().oneOf(std.objectValues($.HorizontalAlign)),
        core.field('vertical_align').required().oneOf(std.objectValues($.VerticalAlign)),
        core.field('mx').required().number(),
        core.field('my').required().number(),
      ],
    }],
  },

  Rect: $.Element + {
    local this = self,

    tag:: 'rect',
    size:: null,
    location:: null,
    roundedness:: math2d.zeros(),
    fill: 'none',
    stroke: 'black',

    __validate__+:: [{
      name: 'svg.Rect',
      validators: [
        core.field('size').required().object(),
        core.field('location').required().object(),
        core.field('roundedness').required().object(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        width: this.size.x,
        height: this.size.y,
        x: this.location.x,
        y: this.location.y,
        rx: utils.elseNull(this.roundedness.x != 0, this.roundedness.x),
        ry: utils.elseNull(this.roundedness.y != 0, this.roundedness.y),
      },
    },
  },

  rect(size, location, roundedness=math2d.zeros()):: $.Rect + {
    size:: math2d.vec(size),
    location:: math2d.vec(location),
    roundedness:: math2d.vec(roundedness),
  },

  Circle: $.Element + {
    local this = self,

    tag:: 'circle',
    center:: null,
    radius:: null,

    __validate__+:: [{
      name: 'svg.Circle',
      validators: [
        core.field('center').required().typeAny(['object', 'array']),
        core.field('radius').required().typeAny(['number', 'string']),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        cx: this.center.x,
        cy: this.center.y,
        r: this.radius,
      },
    },
  },

  circle(center, radius):: $.Circle + {
    center:: math2d.vec(center),
    radius:: radius,
  },

  Line: $.Element + {
    local this = self,

    tag:: 'line',
    p1:: null,
    p2:: null,

    __validate__+:: [{
      name: 'svg.Line',
      validators: [
        core.field('p1').required().object(),
        core.field('p2').required().object(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        x1: this.p1.x,
        y1: this.p1.y,
        x2: this.p2.x,
        y2: this.p2.y,
      },
    },
  },

  line(p1, p2):: $.Line + {
    p1:: math2d.vec(p1),
    p2:: math2d.vec(p2),
  },

  Polyline: $.Element + {
    local this = self,

    tag:: 'polyline',
    points:: null,

    __validate__+:: [{
      name: 'svg.Polyline',
      validators: [
        core.field('points').required().arrayOfObject(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        points: manifest.templateEach('%s,%s', ' ', this.points, function(x) x.coords()),
      },
    },
  },

  polyline(points):: $.Polyline + {
    points:: [math2d.vec(p) for p in points],
  },

  Polygon: $.Element + {
    local this = self,

    tag:: 'polygon',
    points:: null,

    __validate__+:: [{
      name: 'svg.Polygon',
      validators: [
        core.field('points').required().arrayOfObject(),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        points: manifest.templateEach('%s,%s', ' ', this.points, function(x) x.coords()),
      },
    },
  },

  polygon(points):: $.Polygon + {
    points:: [math2d.vec(p) for p in points],
  },

  Path: $.Element + {
    local this = self,

    tag:: 'path',
    cmds:: null,
    __validate__+:: [{
      name: 'svg.Path',
      validators: [
        core.field('cmds').required().arrayOf('object'),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        d: std.join(' ', [x.render() for x in this.cmds]),
      },
    },

    Command: core.Object + {
      code:: null,
      params:: [],
      __validate__+:: [{
        name: 'svg.Path.Command',
        validators: [
          core.field('code').required().string(),
          core.field('params').required().arrayOfAny(['string', 'object'])
        ],
      }],

      render():: std.join(' ', [self.code] + self.params)
    },

    // p is the point to move to
    move(p):: $.Path.Command + {
      code:: 'M',
      params:: math2d.vec(p).coords(),
    },

    // d is the relative distance to the point to move to
    moveRel(d):: $.Path.Command + {
      code:: 'm',
      params:: math2d.vec(d).coords(),
    },

    // p is the ending point
    line(p):: $.Path.Command + {
      code:: 'L',
      params:: math2d.vec(p).coords(),
    },

    // d is the relative distance to the ending point
    lineRel(d):: $.Path.Command + {
      code:: 'l',
      params:: math2d.vec(d).coords(),
    },

    // x is the x coordinate of the ending point
    horizontalLine(x):: $.Path.Command + {
      code:: 'H',
      params:: [x],
    },

    // dx is the relative horizontal distance to the ending point
    horizontalLineRel(dx):: $.Path.Command + {
      code:: 'h',
      params:: [dx],
    },

    // y is the y coordinate of the ending point
    verticalLine(y):: $.Path.Command + {
      code:: 'V',
      params:: [y],
    },

    // dy is the relative vertical distance to the ending point
    verticalLineRel(dy):: $.Path.Command + {
      code:: 'v',
      params:: [dy],
    },

    close():: $.Path.Command + {
      code:: 'v',
      params:: [],
    },

    // p1 is the control point, p2 is the ending point
    quadraticBezier(p1, p2):: $.Path.Command + {
      code:: 'Q',
      params:: math2d.vec(p1).coords() + math2d.vec(p2).coords(),
    },

    // d1 is the relative distance to the control point, d2 is the relative
    // distance to the ending point
    quadraticBezierRel(d1, d2):: $.Path.Command + {
      code:: 'q',
      params:: math2d.vec(d1).coords() + math2d.vec(d2).coords(),
    },

    // p1 and p2 are control points, p3 is the ending point
    cubicBezier(p1, p2, p3):: $.Path.Command + {
      code:: 'C',
      params:: math2d.vec(p1).coords() + math2d.vec(p2).coords() + math2d.vec(p3).coords(),
    },

    // d1 and d2 are relative distances to control points, d3 is relative
    // distance to the ending point
    cubicBezierRel(d1, d2, d3):: $.Path.Command + {
      code:: 'c',
      params:: math2d.vec(d1).coords() + math2d.vec(d2).coords() + math2d.vec(d3).coords(),
    },

    // p2 is the ending point of this quadratic bezier curve. The control point
    // is inferred from another quadratic bezier curve command that precedes
    // this command, and is a reflection of the control point of that curve
    // across its ending point (aka the starting point of this curve)
    smoothQuadraticBezier(p2):: $.Path.Command + {
      code:: 'T',
      params:: math2d.vec(p2).coords(),
    },

    // Like smoothQuadraticBezier(), but with relative distances instead of
    // absolute points
    smoothQuadraticBezierRel(d2):: $.Path.Command + {
      code:: 't',
      params:: math2d.vec(d2).coords(),
    },

    // p2 is the second control point of this cubic bezier curve, p2 is the
    // ending point. The first control point is inferred from a cubic or smooth
    // bezier curve command that precedes this command, and is a reflection of
    // the second control point of that curve across its ending point (aka the
    // starting point of this curve)
    smoothCubicBezier(p2, p3):: $.Path.Command + {
      code:: 'S',
      params:: math2d.vec(p2).coords() + math2d.vec(p3).coords(),
    },

    // Like smoothCubicBezier(), but with relative distances instead of
    // absolute points
    smoothCubicBezierRel(d2, d3):: $.Path.Command + {
      code:: 'd',
      params:: math2d.vec(d2).coords() + math2d.vec(d3).coords(),
    },

    // TODO
    ellipticalArc(p, opts={}):: $.Path.Command + {
      local point_normalized = math2d.vec(p),
      code:: 'A',
      rx:: null,
      ry:: null,
      x_axis_rotation:: 0,
      large_arc_flag:: false,
      sweep_flag:: false,
      __validate__+:: [{
        name: 'svg.Path.ellipticalArc',
        validators: [
          core.field('rx').required().number(),
          core.field('ry').required().number(),
        ],
      }],
      params:: [
        self.rx, self.ry, self.x_axis_rotation,
        boolAsInt(opts.large_arc_flag), boolAsInt(opts.sweep_flag),
        point_normalized.x, point_normalized.y,
      ],
    } + opts,

    // TODO
    ellipticalArcRel(d, opts={}):: $.Path.Command + {
      local delta_normalized = math2d.vec(d),
      code:: 'a',
      rx:: null,
      ry:: null,
      x_axis_rotation:: 0,
      large_arc_flag:: false,
      sweep_flag:: false,
      __validate__+:: [{
        name: 'svg.Path.ellipticalArcRel',
        validators: [
          core.field('rx').required().number(),
          core.field('ry').required().number(),
        ],
      }],
      params:: [
        self.rx, self.ry, self.x_axis_rotation,
        boolAsInt(opts.large_arc_flag), boolAsInt(opts.sweep_flag),
        delta_normalized.x, delta_normalized.y,
      ],
    } + opts,
  },
  
  path(cmds):: $.Path + {
    cmds:: cmds,
  },
}