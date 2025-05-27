local test = import "jsonnetunit/jsonnetunit/test.libsonnet";
local matcher = import "jsonnetunit/jsonnetunit/matcher.libsonnet";

local core = import "core/core.libsonnet";
local math2d = import "core/math2d.libsonnet";
local utils = import "core/utils.libsonnet";

local svg = import "./svg.libsonnet";

test.suite({
  ['test_%s' % [tc.name]]: {
    actual: core.validated(tc.instance).xmlPretty(),
    expect: utils.trim(tc.expect),
  }
  for tc in [
    {
      name: 'textbox',
      instance: svg.TextBox + {
        size:: math2d.vec(100, 100),
        location:: math2d.vec(10, 10),
        text_content:: 'foobar',
      },
      expect: |||
        <rect height="100" width="100" x="10" y="10">
          <text textLength="100">foobar</text>
        </rect>
      |||,
    },
    {
      name: 'textbox_centered',
      instance: svg.TextBox + {
        size:: math2d.vec(100, 100),
        location:: math2d.vec(10, 10),
        text_content:: 'foobar',
        text:: svg.CenteredTextMixin + super.text,
      },
      expect: |||
        <rect height="100" width="100" x="10" y="10">
          <text dominant-baseline="middle" text-anchor="middle" textLength="100">foobar</text>
        </rect>
      |||,
    },
  ]
}) + {
  // Add a matcher with better output for multiline strings
  matchers+: {
    expect+: {
      matcher: function(actual, expected)
        super.matcher(actual, expected) + {
          positiveMessage: |||
            FAILED

              actual:
            %s

              expect:
            %s
          ||| % [actual, expected],
      },
    },
  },
}