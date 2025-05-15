local test = import "jsonnetunit/jsonnetunit/test.libsonnet";
local matcher = import "jsonnetunit/jsonnetunit/matcher.libsonnet";

local validate = import "./validate.libsonnet";
local utils = import "./utils.libsonnet";

local valid_child = validate.Validate + {
  garply: true,
  __validate__+: [{
    name: 'validate_test.ChildClass',
    validators+: [
      validate.field('garply').required().boolean(),
    ],
  }],
};

local invalid_child = validate.Validate + {
  garply: null,
  __validate__+: [{
    name: 'validate_test.ChildClass',
    validators+: [
      validate.field('garply').required(),
    ],
  }],
};

local invalid_child_with_debug_field = validate.Validate + {
  garply: null,
  grundle: 7,
  __validate__+: [{
    name: 'validate_test.ChildClass',
    validators+: [
      validate.field('garply').required(),
    ],
    debug+: ['grundle'],
  }],
};


test.suite(
  {
    // Have a few tests that check raw Validators rather than validate.Validate
    // instances since these can be easier to debug if everything gets borked
    ['test_validator_%s' % [tc.name]]: {
      actual: tc.validator.validate(tc.value).describe(),
      expect: utils.trim(tc.expect),
    }
    for tc in [
      {
        name: 'pass_custom',
        validator: validate.funcValidator(function(_) null),
        value: {
          foo: 'bar',
        },
        expect: |||
          Valid
        |||,
      },
      {
        name: 'fail_custom',
        validator: validate.funcValidator(function(_) 'fail'),
        value: {
          foo: 'bar',
        },
        expect: |||
          Validation failure:
            fail
        |||,
      },
      {
        name: 'field_type',
        validator: validate.field('foo').number(),
        value: {
          foo: 'bar',
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Found type `string`, expected `number`
        |||,
      },
    ]
  } + {
    ['test_validate_%s' % [tc.name]]: {
      actual: validate.validate(tc.instance).describe(),
      expect: utils.trim(tc.expect),
    }
    for tc in [
      #{
      #  name: 'valid',
      #  instance: validate.Validate + {
      #    foo: 3,
      #    bar: [7, null],
      #    baz: valid_child,
      #    qux: [valid_child, null],
      #    corg: { child: valid_child },
      #    __validate__+:: [{
      #      name: 'validate_test.TestClass',
      #      validators+: [
      #        validate.field('foo')
      #          .required()
      #          .number()
      #          .typeAny(['number'])
      #          .gt(2)
      #          .gte(3)
      #          .lt(4)
      #          .lte(3)
      #          .neq(5)
      #          .oneOf([3])
      #          .check(function(x) if x == 3 then null else '<message>'),
      #        validate.field('bar').nonEmpty().arrayOf('number').ignoreNulls(),
      #        validate.field('baz').child(),
      #        validate.field('qux').children().ignoreNulls(),
      #        validate.field('corg').children(),
      #      ],
      #    }],
      #  },
      #  expect: |||
      #    Valid
      #  |||,
      #},
      {
        name: 'field_unset',
        instance: validate.Validate + {
          __validate__+:: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').required(),
            ],
          }],
        },
        expect: |||
          Validation failure:
            Validated field `foo` is unset
          In validate_test.TestClass
        |||,
      },
      {
        name: 'missing_required',
        instance: validate.Validate + {
          foo: null,
          __validate__+:: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').required(),
            ],
          }],
        },
        expect: |||
          Validation failure:
            Required field `foo` is null
          In validate_test.TestClass
        |||,
      },
      {
        name: 'wrong_type',
        instance: validate.Validate + {
          foo: 'bar',
          __validate__+:: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').number(),
            ],
          }]
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Found type `string`, expected `number`
          In validate_test.TestClass
        |||,
      },
      {
        name: 'wrong_type_one_of',
        instance: validate.Validate + {
          foo: true,
          __validate__+:: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').typeAny(['number', 'string']),
            ],
          }]
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Found type `boolean`, expected one of (`number`, `string`)
          In validate_test.TestClass
        |||,
      },
      {
        name: 'wrong_element_type',
        instance: validate.Validate + {
          foo: ['bar'],
          __validate__+:: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').arrayOfNumber(),
              #validate.field('foo').elementType('number'),
            ],
          }]
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Element `0`:
                Found type `string`, expected `number`
          In validate_test.TestClass
        |||,
      },
      {
        name: 'null_element_type',
        instance: validate.Validate + {
          foo: ['bar', null],
          __validate__+:: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').arrayOfString(),
            ],
          }]
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Element `1`:
                Found type `null`, expected `string`
          In validate_test.TestClass
        |||,
      },
      {
        name: 'wrong_element_type_one_of',
        instance: validate.Validate + {
          foo: [12, null],
          __validate__+:: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').elementTypeAny(['number', 'string']),
            ],
          }]
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Element `1`:
                Found type `null`, expected one of (`number`, `string`)
          In validate_test.TestClass
        |||,
      },
      {
        name: 'not_gt',
        instance: validate.Validate + {
          foo: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').gt(3)
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Value `3` is not greater than bound `3`
          In validate_test.TestClass
        |||,
      },
      {
        name: 'not_gte',
        instance: validate.Validate + {
          foo: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').gte(4)
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Value `3` is not greater than or equal to bound `4`
          In validate_test.TestClass
        |||,
      },
      {
        name: 'not_lt',
        instance: validate.Validate + {
          foo: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').lt(3)
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Value `3` is not less than bound `3`
          In validate_test.TestClass
        |||,
      },
      {
        name: 'not_lte',
        instance: validate.Validate + {
          foo: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').lte(2)
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Value `3` is not less than or equal to bound `2`
          In validate_test.TestClass
        |||,
      },
      {
        name: 'not_neq',
        instance: validate.Validate + {
          foo: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').neq(3)
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Value `3` is disallowed
          In validate_test.TestClass
        |||,
      },
      {
        name: 'not_one_of',
        instance: validate.Validate + {
          foo: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').oneOf([2, 4])
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Value `3` is not one of the expected options (`2`, `4`)
          In validate_test.TestClass
        |||,
      },
      {
        name: 'not_non_empty',
        instance: validate.Validate + {
          foo: [],
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').nonEmpty()
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              Value has length 0, expected non-empty
          In validate_test.TestClass
        |||,
      },
      {
        name: 'failed_custom_check',
        instance: validate.Validate + {
          foo: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').check(function(x) if x == 3 then '<message>' else null)
            ],
          }],
        },
        expect: |||
          Validation failure:
            Field `foo`:
              <message>
          In validate_test.TestClass
        |||,
      },
      {
        name: 'invalid_child',
        instance: validate.Validate + {
          foo: invalid_child,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').child(),
            ],
          }],
        },
        expect: |||
          Validation failure:
            Required field `garply` is null
          In validate_test.ChildClass

          From field `foo` in validate_test.TestClass
        |||,
      },
      {
        name: 'invalid_child_in_array',
        instance: validate.Validate + {
          foo: [valid_child, invalid_child],
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').children(),
            ],
          }],
        },
        expect: |||
          Validation failure:
            Required field `garply` is null
          In validate_test.ChildClass

          From field `foo[1]` in validate_test.TestClass
        |||,
      },
      {
        name: 'invalid_child_in_object',
        instance: validate.Validate + {
          foo: {
            bar: valid_child,
            baz: invalid_child,
          },
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').children(),
            ],
          }],
        },
        expect: |||
          Validation failure:
            Required field `garply` is null
          In validate_test.ChildClass

          From field `foo['baz']` in validate_test.TestClass
        |||,
      },
      {
        name: 'debug_fields',
        instance: validate.Validate + {
          foo: null,
          bar: 'baz',
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').required(),
            ],
            debug+: ['bar'],
          }],
        },
        expect: |||
          Validation failure:
            Required field `foo` is null
          In validate_test.TestClass
            Instance fields:
              bar: baz
        |||,
      },
      {
        name: 'subclass',
        instance: validate.Validate + {
          foo: null,
          __validate__+: [{
            name: 'validate_test.GrandparentClass',
          }, {
            name: 'validate_test.ParentClass',
            validators+: [
              validate.field('foo').required(),
            ],
          }, {
            name: 'validate_test.ChildClass',
          }],
        },
        expect: |||
          Validation failure:
            Required field `foo` is null
          In validate_test.ParentClass (ancestor of validate_test.ChildClass)
        |||,
      },
      {
        name: 'subclass_debug_fields',
        instance: validate.Validate + {
          foo: null,
          __validate__+: [{
            name: 'validate_test.GrandparentClass',
            validators+: [
              validate.field('foo').required(),
            ],
            debug+: ['foo'],
          }, {
            name: 'validate_test.ParentClass',
            validators+: [
              validate.field('bar').required(),
            ],
            debug+: ['bar'],
          }, {
            name: 'validate_test.ChildClass',
            validators+: [
              validate.field('baz').required(),
            ],
            debug+: ['baz'],
          }],
        } + {
          bar: 2,
          baz: 3,
        },
        expect: |||
          Validation failure:
            Required field `foo` is null
          In validate_test.GrandparentClass (ancestor of validate_test.ChildClass)
            Instance fields:
              foo: null
              bar: 2
              baz: 3
        |||,
      },
      {
        name: 'containment_debug_fields',
        instance: validate.Validate + {
          foo: invalid_child_with_debug_field,
          bar: 3,
          __validate__+: [{
            name: 'validate_test.TestClass',
            validators+: [
              validate.field('foo').child(),
            ],
            debug+: ['bar'],
          }],
        },
        expect: |||
          Validation failure:
            Required field `garply` is null
          In validate_test.ChildClass
            Instance fields:
              grundle: 7

          From field `foo` in validate_test.TestClass
            Instance fields:
              bar: 3
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