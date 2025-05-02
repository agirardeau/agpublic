local core = import './core.libsonnet';

{
  pi: 3.141592653589793,
  deg2rad(deg): deg * $.pi / 180,
  rad2deg(rad): rad * 180 / $.pi,

  // Convenience method for creating a vector from variously typed input.
  // Allowed signatures:
  //   vec(1, 2)
  //   vec([1, 2])
  //   vec({x: 1, y: 2})
  vec(first_arg, second_arg=null)::
    if second_arg != null then
      assert std.isNumber(first_arg) && std.isNumber(second_arg) : 'math2d.vec(): If two arguments are provided, they must both be numbers. Found %s and %s' % [std.type(first_arg), std.type(second_arg)];
      $.Vector + {
        x: first_arg,
        y: second_arg,
      }
    else if std.isArray(first_arg) then
      assert std.length(first_arg) == 2 : 'math2d.vec(): Expected array input to be length 2, found length %s' % std.type(first_arg);
      $.Vector + {
        x: first_arg[0],
        y: first_arg[1],
      }
    else if std.isObject(first_arg) then
      core.validated($.Vector + first_arg)
    #else if first_arg == null then
    #  null
    else
      error 'math2d.vec(): Expected an array, object, or two numbers. Found %s' % std.type(first_arg),

  polar(radius, azimuthDegrees):: $.Vector + {
    x: radius * std.cos($.deg2rad(azimuthDegrees)),
    y: radius * std.sin($.deg2rad(azimuthDegrees)),
  },

  origin():: $.Vector + {
    x: 0,
    y: 0,
  },

  Vector: core.Object + {
    local this = self,

    x: null,
    y: null,

    __validate__+:: [{
    name: 'math.2d.Vector',
      validators: [
        core.field('x').required().number(),
        core.field('y').required().number(),
      ],
    }],

    coords():: [self.x, self.y],

    add(other, other_y=null)::
      local other_normalized = $.vec(other, other_y);
      $.Vector + {
        x: this.x + other_normalized.x,
        y: this.y + other_normalized.y,
      },
  },
}