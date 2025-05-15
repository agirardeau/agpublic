local test = import "jsonnetunit/jsonnetunit/test.libsonnet";
local matcher = import "jsonnetunit/jsonnetunit/matcher.libsonnet";

local core = import "core/core.libsonnet";
local utils = import "core/utils.libsonnet";

local css = import "./css.libsonnet";

test.suite(
  {
    ['test_render_%s' % [tc.name]]: {
      actual: core.validated(tc.instance).render(),
      expect: utils.trim(tc.expect),
    }
    for tc in [
      {
        name: 'import',
        instance: css.Import + {
          url: 'http://<domain>/<path>',
        },
        expect: |||
          @import url("http://<domain>/<path>");
        |||,
      },
      {
        name: 'font_face',
        instance: css.FontFace + {
          font_family_name: 'Trickster',
          sources: [
            css.list([
              css.fns.url('trickster-COLRv1.otf'),
              css.fns.format('opentype'),
              css.fns.tech(css.raw('color-COLRv1')),
            ]),
            css.list([
              css.fns.url('trickster-outline.otf'),
              css.fns.format('opentype'),
            ]),
            css.list([
              css.fns.url('trickster-outline.woff'),
              css.fns.format('woff'),
            ]),
          ]
        },
        expect: |||
          @font-face {
            font-family: "Trickster";
            src: 
              local("Trickster"),
              url("trickster-COLRv1.otf") format("opentype") tech(color-COLRv1),
              url("trickster-outline.otf") format("opentype"),
              url("trickster-outline.woff") format("woff");
          }
        |||,
      },
    ]
  }
) + {
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