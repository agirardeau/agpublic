local core = import 'core/core.libsonnet';
local manifest = import 'core/manifest.libsonnet';
local math2d = import 'core/math2d.libsonnet';
local utils = import 'core/utils.libsonnet';

local mathml = import './mathml.libsonnet';
local xml = import './xml.libsonnet';

local boolAsInt(bool) = if bool then 1 else 0;

local replaceUnderscores = function(x) std.strReplace(x, '_', '-');

{
  Element: xml.StyleElement + {
    xml(options={}):: super.xml({
      snake_to_kebab_case: true,
      key_mutators+: utils.singletonArrayIf(self.snake_to_kebab_case, utils.snakeCaseToKebabCase),
    } + options),
  },

  Svg: $.Element + {
    tag:: 'svg',
    is_inline:: false,
    xmlns: if self.is_inline then null else 'http://www.w3.org/2000/svg',
    size:: null,
    width: self.size.x,
    height: self.size.y,
    origin:: $.Svg.Origin.TOP_LEFT,
    viewBox: 
      if self.origin == $.Svg.Origin.TOP_CENTER then
        manifest.template('%s 0 %s %s', [-self.width/2, self.width, self.height])
      else if self.origin == $.Svg.Origin.LEFT_CENTER then
        manifest.template('0 %s %s %s', [-self.height/2, self.width, self.height])
      else if self.origin == $.Svg.Origin.CENTER then
        manifest.template('%s %s %s %s', [-self.width/2, -self.height/2, self.width, self.height])
      else manifest.template('0 0 %s %s', [self.width, self.height]),

    __validate__+:: [{
      name: 'svg.Svg',
      validators: [
        core.field('width').required(),
        core.field('height').required(),
        core.field('origin').string(),
      ],
    }],

    Origin:: {
      TOP_LEFT: 'top-left',
      TOP_CENTER: 'top-center',
      LEFT_CENTER: 'left-center',
      CENTER: 'center',
    },
  },

  ForeignObject: $.Element + {
    tag:: 'foreignObject',
    size:: null,
    width: utils.ifNotNull(self.size, self.size.x),
    height: utils.ifNotNull(self.size, self.size.y),
    location:: null,
    x: utils.ifNotNull(self.location, self.location.x) - self.width/2,
    y: utils.ifNotNull(self.location, self.location.y) - self.height/2,
    __validate__+:: [{
      name: 'svg.ForeignObject',
      validators: [
        core.field('x').required(),
        core.field('y').required(),
        core.field('width').required(),
        core.field('height').required(),
      ],
    }],
  },

  MathML: $.ForeignObject + {
    local this = self,
    content:: null,
    mathml:: mathml.math(self.content) + {
      #style+:: {
      #  margin: 'auto',
      #},
    },
    body:: xml.StyleElement + {
      tag:: 'body',
      xmlns: 'http://www.w3.org/1999/xhtml',
      has:: [this.mathml],
      style+:: {
        #display: 'flex',
        #flex_direction: 'column',
        display: 'grid',
        justify_content: 'center',
        align_items: 'center',
      },
    },
    has:: [this.body],
  },

  Circle: $.Element + {
    local this = self,

    tag:: 'circle',
    center:: null,
    radius:: null,
    local center_normalized = math2d.vec(this.center),

    __validate__+:: [{
      name: 'svg.Circle',
      validators: [
        core.field('center').required().typeAny(['object', 'array']),
        core.field('radius').required().typeAny(['number', 'string']),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        cx: center_normalized.x,
        cy: center_normalized.y,
        r: this.radius,
      },
    },
  },

  Line: $.Element + {
    local this = self,

    tag:: 'line',
    p1:: null,
    p2:: null,
    local p1_normalized = math2d.vec(this.p1),
    local p2_normalized = math2d.vec(this.p2),

    __validate__+:: [{
      name: 'svg.Line',
      validators: [
        core.field('p1').required().typeAny(['object', 'array']),
        core.field('p2').required().typeAny(['object', 'array']),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        x1: p1_normalized.x,
        y1: p1_normalized.y,
        x2: p2_normalized.x,
        y2: p2_normalized.y,
      },
    },
  },

  Polyline: $.Element + {
    local this = self,

    tag:: 'polyline',
    points:: null,
    local points_normalized = [math2d.vec(p) for p in self.points],

    __validate__+:: [{
      name: 'svg.Polyline',
      validators: [
        core.field('points').required().arrayOfAny(['object', 'array']),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        points: std.join(' ', [
          '%s,%s' % [p.x, p.y]
          for p in points_normalized
        ]),
      },
    },
  },

  Polygon: $.Element + {
    local this = self,

    tag:: 'polygon',
    points:: null,
    local points_normalized = [math2d.vec(p) for p in self.points],

    __validate__+:: [{
      name: 'svg.Polygon',
      validators: [
        core.field('points').required().arrayOfAny(['object', 'array']),
      ],
    }],
    __manifest__+:: {
      overlay+: {
        points: std.join(' ', [
          '%s,%s' % [p.x, p.y]
          for p in points_normalized
        ]),
      },
    },
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
      params:: math2d.vec(p),
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

    horizontalLine(x):: $.Path.Command + {
      code:: 'H',
      params:: [x],
    },

    horizontalLineRel(dx):: $.Path.Command + {
      code:: 'h',
      params:: [dx],
    },

    verticalLine(y):: $.Path.Command + {
      code:: 'V',
      params:: [y],
    },

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
      code:: 'c',
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
      code:: 'Q',
      params:: math2d.vec(p2).coords(),
    },

    // Like smoothQuadraticBezier(), but with relative distances instead of
    // absolute points
    smoothQuadraticBezierRel(d2):: $.Path.Command + {
      code:: 'Q',
      params:: math2d.vec(d2).coords(),
    },

    // p2 is the second control point of this cubic bezier curve, p2 is the
    // ending point. The first control point is inferred from a cubic or smooth
    // bezier curve command that precedes this command, and is a reflection of
    // the second control point of that curve across its ending point (aka the
    // starting point of this curve)
    smoothCubicBezier(p2, p3):: $.Path.Command + {
      code:: 'Q',
      params:: math2d.vec(p2).coords() + math2d.vec(p3).coords(),
    },

    // Like smoothCubicBezier(), but with relative distances instead of
    // absolute points
    smoothCubicBezierRel(d2, d3):: $.Path.Command + {
      code:: 'Q',
      params:: math2d.vec(d2).coords() + math2d.vec(d3).coords(),
    },

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
}