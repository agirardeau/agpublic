local test = import "jsonnetunit/jsonnetunit/test.libsonnet";
local matcher = import "jsonnetunit/jsonnetunit/matcher.libsonnet";

local xml = import "./xml.libsonnet";
local utils = import "core/utils.libsonnet";

test.suite({
  ['test_%s' % [tc.name]]: {
    actual: tc.instance.xmlPretty(utils.get(tc, 'options', {})),
    expect: utils.trim(tc.expect),
  }
  for tc in [
    {
      name: 'nested',
      instance: xml.Element + {
        tag:: 'foo',
        my_attr: 'bar',
        has: [
          xml.Element + {
            tag: 'baz',
            nested_attr: 'qux',
          },
        ],
      },
      expect: |||
        <foo my_attr="bar">
          <baz nested_attr="qux"></baz>
        </foo>
      |||,
    },
    {
      name: 'text_content',
      instance: xml.Element + {
        tag:: 'foo',
        has: [
          'bar',
          xml.Element + {
            tag: 'baz',
            has: ['qux'],
          },
        ],
      },
      expect: |||
        <foo>
          bar
          <baz>qux</baz>
        </foo>
      |||,
    },
    {
      name: 'manifest_options',
      instance: xml.Element + {
        local this = self,
        tag:: 'foo',
        pruned: null,
        bar: 3,
        qux:: 5,
        tag_attr: 10,
        __manifest__+:: {
          rename+: {
            bar: 'baz',
            tag_attr: 'tag',
          },
          overlay+: {
            qux: this.qux + 2,
          },
        },
      },
      expect: |||
        <foo baz="3" qux="7" tag="10"></foo>
      |||,
    },
    {
      name: 'mutators',
      instance: xml.Element + {
        local this = self,
        tag:: 'foo_bar',
        baz_qux: 0.12345,
        has: [
          0.12345
        ],
      },
      options: {
        key_mutators: [utils.snakeCaseToKebabCase],
        float_precision: 3,
      },
      expect: |||
        <foo-bar baz-qux="0.123">
          0.123
        </foo-bar>
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

              got:
            %s

              want:
            %s
          ||| % [actual, expected],
      },
    },
  },
}