local test = import "jsonnetunit/jsonnetunit/test.libsonnet";
local matcher = import "jsonnetunit/jsonnetunit/matcher.libsonnet";

local manifest = import "./manifest.libsonnet";
local utils = import "./utils.libsonnet";

test.suite({
  ['test_%s' % [tc.name]]: {
    #actual: manifest.manifest(tc.instance),
    actual: tc.instance.jsonPretty(),
    expect: utils.trim(tc.expect),
  }
  for tc in [
    {
      name: 'rename',
      instance: manifest.Manifest + {
        foo: 2,
        qux: 3,
        __manifest__+:: {
          rename+: {
            foo: "bar",
          },
        },
      },
      expect: |||
        {
          "bar": 2,
          "qux": 3
        }
      |||,
    },
    {
      name: 'overlay',
      instance: manifest.Manifest + {
        local this = self,
        foo:: 2,
        qux: 3,
        __manifest__+:: {
          overlay+: {
            bar: this.foo,
          },
        },
      },
      expect: |||
        {
          "bar": 2,
          "qux": 3
        }
      |||,
    },
    {
      name: 'dont_prune',
      instance: manifest.Manifest + {
        foo: null,
        bar: [],
        baz: {},
        qux: false,
      },
      expect: |||
        {
          "bar": [

          ],
          "baz": {

          },
          "foo": null,
          "qux": false
        }
      |||,
    },
    {
      name: 'prune_null',
      instance: manifest.Manifest + {
        foo: null,
        __manifest__+:: {
          prune_null: true,
        },
      },
      expect: |||
        {

        }
      |||,
    },
    {
      name: 'prune_empty_list',
      instance: manifest.Manifest + {
        foo: [],
        __manifest__+:: {
          prune_empty_list: true,
        },
      },
      expect: |||
        {

        }
      |||,
    },
    {
      name: 'prune_empty_object',
      instance: manifest.Manifest + {
        foo: {},
        __manifest__+:: {
          prune_empty_object: true,
        },
      },
      expect: |||
        {

        }
      |||,
    },
    {
      name: 'prune_false',
      instance: manifest.Manifest + {
        foo: false,
        __manifest__+:: {
          prune_false: true,
        },
      },
      expect: |||
        {

        }
      |||,
    },
    {
      name: 'nested_rename',
      instance: manifest.Manifest + {
        foo: manifest.Manifest + {
          baz: 2,
          __manifest__+:: {
            rename+: {
              baz: "qux",
            },
          },
        },
        __manifest__+:: {
          rename+: {
            foo: "bar",
          },
        },
      },
      expect: |||
        {
          "bar": {
            "qux": 2
          }
        }
      |||,
    },
    {
      name: 'nested_in_raw_object',
      instance: manifest.Manifest + {
        foo: {
          bar: manifest.Manifest + {
            baz: 2,
            __manifest__+:: {
              rename+: {
                baz: "qux",
              },
            },
          },
        },
      },
      expect: |||
        {
          "foo": {
            "bar": {
              "qux": 2
            }
          }
        }
      |||,
    },
    {
      name: 'nested_in_array',
      instance: manifest.Manifest + {
        foo: [
          manifest.Manifest + {
            bar: 2,
            __manifest__+:: {
              rename+: {
                bar: "qux",
              },
            },
          },
          3,
          "garply",
          true,
          null,
        ],
      },
      expect: |||
        {
          "foo": [
            {
              "qux": 2
            },
            3,
            "garply",
            true,
            null
          ]
        }
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