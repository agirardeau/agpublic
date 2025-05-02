local test = import "jsonnetunit/jsonnetunit/test.libsonnet";
local matcher = import "jsonnetunit/jsonnetunit/matcher.libsonnet";

local utils = import "./utils.libsonnet";

test.suite({
  ['test_%s' % [tc.name]]: {
    actual: tc.actual,
    expect: tc.expect,
  }
  for tc in [
    {
      name: 'applyAll_empty',
      actual: utils.applyAll('foo', []),
      expect: 'foo',
    },
    {
      name: 'applyAll_multiple',
      actual: utils.applyAll('foo', [
        function(res) res + 'bar',
        function(res) res + 'baz',
      ]),
      expect: 'foobarbaz',
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

              got:
            %s

              want:
            %s
          ||| % [actual, expected],
      },
    },
  },
}