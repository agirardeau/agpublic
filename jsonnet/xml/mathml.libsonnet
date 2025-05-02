local core = import 'core/core.libsonnet';

local xml = import './xml.libsonnet';

local maybeWrapInArray(x) = if std.isArray(x) then x else [x];

{
  Element: xml.StyleElement,

  math(content):: $.Element + {
    tag:: 'math',
    xmlns: 'http://www.w3.org/1998/Math/MathML',
    display: 'block',
    has:: maybeWrapInArray(content),
  },

  identifier(id):: $.Element + {
    tag:: 'mi',
    has:: [id],
  },
  
  operator(op):: $.Element + {
    tag:: 'mo',
    has:: [op],
  },

  numeric(num):: $.Element + {
    tag:: 'mn',
    has:: [num],
  },

  row(content):: $.Element + {
    tag:: 'mrow',
    has:: maybeWrapInArray(content),
  },
  
  fraction(num, denom):: $.Element + {
    tag:: 'mfrac',
    numerator:: $.row(num),
    denominator:: $.row(denom),
    has:: [self.numerator, self.denominator],
  },

  sqrt(content):: xml.Element + {
    tag:: 'msqrt',
    has:: maybeWrapInArray(content),
  },

  superscript(base, superscript):: xml.Element + {
    tag:: 'msup',
    has:: [base, superscript],
  },

  dot: $.operator('⋅'),
}