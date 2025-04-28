local utils = import './utils.libsonnet';

local formatListOfStrings(strings) =
  if std.length(strings) == 0 then '()'
  else '(`%s`)' % [std.join('`, `', strings)];

local private = {
  ValidationStanza: {
    name: null,
    validators: [],
    debug: [],
  },

  ValidationOptions: {
    verbose: false,
  },

  ValidationContext: {
    instance_context: null,
    field_context: null,

    describeClass()::
      if self.instance_context.class == self.instance_context.leaf_class
      then self.instance_context.class
      else '%s (ancestor of %s)' % [self.instance_context.class, self.instance_context.leaf_class],

    describeField()::
      local index_type = std.type(self.field_context.element_index);
      if self.field_context.element_index == null
      then self.field_context.name
      else '%s[%s]' % [self.field_context.name, utils.formatValueBrief(self.field_context.element_index)],
    
    debugLines()::
      local obj = self.instance_context.instance;
      local field_lines = utils.fold(
        obj.__validate__,
        [],
        function(res, stanza)
          local stz = private.ValidationStanza + stanza;
          res + [
            '    %s: %s' % [fieldname, if std.objectHasAll(obj, fieldname) then obj[fieldname] else '<unset>']
            for fieldname in stz.debug
          ],
      );
      if std.length(field_lines) == 0 then ''
      else '\n  Instance fields:\n' + std.join('\n', field_lines),

    describe()::
      (
        if self.field_context != null
        then 'From field `%s` in %s' % [self.describeField(), self.describeClass()]
        else 'In %s' % [self.describeClass()]
      ) + self.debugLines(),

    InstanceContext:: {
      class: null,
      leaf_class: null,
      instance: null,
    },

    FieldContext:: {
      name: null,
      element_index: null,  // Used when the field is a collection of children
    },
  },

  // Essentially an array of ValidationContext with some helper methods
  // Construct this from the top of the stack down, i.e. call with*Context()
  // methods with top/most specific/closest to error contexts first.
  ValidationContextStack: {
    local this = self,

    // All non-bottom contexts must have both instance and field context once
    // constructed.
    // During construction, bottom context may have instance context missing.
    stack: [],

    withInstanceContext(instance_context)::
      if std.length(self.stack) == 0
      then self + {
        stack: [private.ValidationContext + {
          instance_context: instance_context,
        }],
      }
      else
        local bottom_context = utils.last(self.stack);
        assert bottom_context.instance_context == null : 'Inserted instance context, expected field context next';
        assert bottom_context.field_context != null : 'Inserted instance context, expected field context next';
        self + {
          stack: utils.slice(this.stack, 0, -1) + [bottom_context + {
            instance_context: instance_context,
          }],
        },

    withFieldContext(field_context)::
      assert std.length(self.stack) == 0 || self.stack[0].instance_context != null : 'Inserted field context, expected instance context next';
      self + {
        stack+: [private.ValidationContext + {
          field_context: field_context,
        }],
      },

    empty():: private.ValidationContextStack,

    describe()::
      utils.fold(
        this.stack,
        '',
        function(res, ctx)
          if res == ''
          then ctx.describe()
          else res + '\n\n' + ctx.describe(),
      ),
  },

  ValidationResult: {
    local this = self,

    is_valid: null,
    failure_message: null,

    success():: self + {
      is_valid: true,
    },

    failure(message):: self + {
      is_valid: false,
      failure_message: message,
    },

    describe()::
      if self.is_valid then 'Valid'
      else 'Validation failure: %s' % [self.failure_message],

    withFieldContext(field_context)::
      if self.is_valid then self
      else private.ValidationResultWithContext + {
        is_valid: this.is_valid,
        failure_message: this.failure_message,
        context_stack: private.ValidationContextStack.withFieldContext(field_context),
      },

    withInstanceContext(instance_context)::
      if self.is_valid then self
      else private.ValidationResultWithContext + {
        is_valid: this.is_valid,
        failure_message: this.failure_message,
        context_stack: private.ValidationContextStack.withInstanceContext(instance_context),
      },
  },

  ValidationResultWithContext: private.ValidationResult + {
    local this = self,

    context_stack: null,

    fromResult(result, context_stack)::
      result + {
        context_stack: context_stack,
      },

    describe()::
      super.describe() + '\n' + self.context_stack.describe(),

    withFieldContext(field_context)::
      self + {
        context_stack: this.context_stack.withFieldContext(field_context),
      },

    withInstanceContext(instance_context)::
      self + {
        context_stack: this.context_stack.withInstanceContext(instance_context),
      },
  },

  debugFieldsForObject(obj):
    utils.fold(
      obj.__validate__,
      {},
      function(res, stanza)
        local stz = private.ValidationStanza + stanza;
        res + stz.debug,
    ),
};

{
  Validate: {
    /// Array of objects with fields:
    ///   name (string): e.g. 'rds.Instance'
    ///   validators (array): array of `validate.Validator` objects
    ///   debug (object): object with fields to print for debugging on failed validation
    __validate__:: [],
  },

  ValidationResult: private.ValidationResult,

  assertValid(obj, options={})::
    local res = $.validate(obj, options);
    assert res.is_valid : res.describe();
    obj,

  validate(obj, options={})::
    local opts = private.ValidationOptions + options;
    utils.fold(
      obj.__validate__,
      $.ValidationResult.success(),
      function(res, stanza)
        local stz = private.ValidationStanza + stanza;
        if !res.is_valid then res
        else utils.fold(
          stz.validators,
          $.ValidationResult.success(),
          function(res, validator)
            if !res.is_valid then res
            else validator.validate(obj, opts),
        ).withInstanceContext(private.ValidationContext.InstanceContext + {
          class: stz.name,
          leaf_class: utils.last(obj.__validate__).name,
          instance: obj,
        }),
    ),

  validated(obj, options={})::
    local res = $.validate(obj, options);
    if !res.is_valid then error(res.describe()) else obj,
  
  // I guess this is just an interface right now, it doesn't have logic
  Validator: {
    validate(obj, options={}):: $.ValidationResult.failure('Validator has no implementation'),
  },

  check(fn):: $.Validator + {
    validate(obj, options={})::
      local output = fn(obj);
      if output == null
      then $.ValidationResult.success()
      else $.ValidationResult.failure(output),
  },

  FieldValidator: $.Validator + {
    local this = self,

    fieldname: null,
    required_:: false,
    type_:: null,
    type_any_of_:: null,
    element_type_:: null,
    element_type_any_of_:: null,
    gt_:: null,
    gte_:: null,
    lt_:: null,
    lte_:: null,
    neq_:: [],
    one_of_:: null,
    non_empty_:: false,
    check_:: null,

    child_:: false,
    children_:: false,
    ignore_nulls_:: false,

    validate(obj, options={})::
      
      local value = if std.objectHasAll(obj, self.fieldname) then obj[self.fieldname] else null;
      local found_type = std.type(value);

      local findInvalidElementType(arr_or_obj, element_type_or_types, ignore_nulls) =
        local is_array = std.type(arr_or_obj) == 'array';
        local checkType(type) =
          if type == 'null' then ignore_nulls
          else if std.type(element_type_or_types) == 'string' then type == element_type_or_types
          else std.member(element_type_or_types, type);
        utils.fold(
          if is_array then arr_or_obj else std.objectKeysValuesAll(arr_or_obj),
          {
            index: -1,
            wrong_type: null,
          },
          function(res, elem)
            local type = if is_array then std.type(elem) else std.type(elem.value);
            if res.wrong_type != null then res
            else {
              index: if is_array then res.index + 1 else elem.key,
              wrong_type: if !checkType(type) then type else null,
            },
        );
      local element_type_check = findInvalidElementType(value, self.element_type_, self.ignore_nulls_);
      local element_type_any_of_check = findInvalidElementType(value, self.element_type_any_of_, self.ignore_nulls_);

      // Always reject fields with validation configured that are unset to catch
      // typos in field names
      if !std.objectHasAll(obj, self.fieldname)
      then $.ValidationResult.failure('Validated field `%s` is unset' % [self.fieldname])

      else if self.required_ && value == null
      then $.ValidationResult.failure('Required field `%s` is null' % [self.fieldname])

      else if value == null
      then $.ValidationResult.success()

      else if self.type_ != null && found_type != self.type_
      then $.ValidationResult.failure('Field `%s` has type `%s`, expected `%s`' % [this.fieldname, found_type, self.type_])

      else if self.type_any_of_ != null && !std.member(self.type_any_of_, found_type)
      then $.ValidationResult.failure('Field `%s` has type `%s`, expected one of %s' % [this.fieldname, found_type, formatListOfStrings(self.type_any_of_)])

      else if self.element_type_ != null && element_type_check.wrong_type != null
      then $.ValidationResult.failure('Field `%s` element `%s` has type `%s`, expected `%s`' % [this.fieldname, element_type_check.index, element_type_check.wrong_type, self.element_type_])

      else if self.element_type_any_of_ != null && element_type_any_of_check.wrong_type != null
      then $.ValidationResult.failure('Field `%s` element `%s` has type `%s`, expected one of %s' % [this.fieldname, element_type_any_of_check.index, element_type_any_of_check.wrong_type, formatListOfStrings(self.element_type_any_of_)])

      else if self.gt_ != null && value <= self.gt_
      then $.ValidationResult.failure('Field `%s` has value `%s`, not greater than bound `%s`' % [this.fieldname, value, self.gt_])

      else if self.gte_ != null && value < self.gte_
      then $.ValidationResult.failure('Field `%s` has value `%s`, not greater than or equal to bound `%s`' % [this.fieldname, value, self.gte_])

      else if self.lt_ != null && value >= self.lt_
      then $.ValidationResult.failure('Field `%s` has value `%s`, not less than bound `%s`' % [this.fieldname, value, self.lt_])

      else if self.lte_ != null && value > self.lte_
      then $.ValidationResult.failure('Field `%s` has value `%s`, not less than or equal to bound `%s`' % [this.fieldname, value, self.lte_])

      else if std.member(self.neq_, value)
      then $.ValidationResult.failure('Field `%s` has disallowed value `%s`' % [this.fieldname, value])

      else if self.one_of_ != null && !std.member(self.one_of_, value)
      then $.ValidationResult.failure('Field `%s` has value `%s`, expected one of %s' % [this.fieldname, value, formatListOfStrings([utils.formatValueBrief(x) for x in self.one_of_])])

      else if self.non_empty_ && std.length(value) == 0
      then $.ValidationResult.failure('Field `%s` is empty %s' % [this.fieldname, std.type(value)])

      else if self.check_ != null && self.check_(value) != null
      then $.ValidationResult.failure('Field `%s` failed check function with message: %s' % [this.fieldname, self.check_(value)])

      else if self.child_
      then $.validate(value).withFieldContext(private.ValidationContext.FieldContext + {
        name: this.fieldname,
      })

      else if self.children_ && found_type == 'array'
      then utils.fold(
        value,
        {
          index: 0,
          result: $.ValidationResult.success(),
        },
        function(res, child) {
          index: res.index + 1,
          result:
            // Short circuit if an invalid child was already found
            if !res.result.is_valid || (this.ignore_nulls_ && child == null)
            then res.result
            else $.validate(child).withFieldContext(private.ValidationContext.FieldContext + {
              name: this.fieldname,
              element_index: res.index,
            }),
        },
      ).result

      else if self.children_ && found_type == 'object'
      then utils.fold(
        std.objectKeysValues(value),
        $.ValidationResult.success(),
        function(res, child_entry)
          // Short circuit if an invalid child was already found
          if !res.is_valid || (this.ignore_nulls_ && child_entry.value == null)
          then res
          else $.validate(child_entry.value).withFieldContext(private.ValidationContext.FieldContext + {
            name: this.fieldname,
            element_index: child_entry.key,
          }),
      )

      else $.ValidationResult.success(),

    required():: self + { required_::: true },

    type(type)::
      assert std.type(type) == 'string' : 'validate.FieldValidator.type(): `type` argument should be a string, found `%s`' % [std.type(type)];
      self + { type_::: type },
    typeAnyOf(types):: self + { type_any_of_::: std.set(types) },
    elementType(type)::
      assert std.type(type) == 'string' : 'validate.FieldValidator.elementType(): `type` argument should be a string, found `%s`' % [std.type(type)];
      self + { element_type_::: type },
    elementTypeAnyOf(types):: self + { element_type_any_of_::: std.set(types) },
    boolean():: self.type('boolean'),
    string():: self.type('string'),
    number():: self.type('number'),
    fn():: self.type('function'),
    array():: self.type('array'),
    object():: self.type('object'),

    arrayOf(type):: self.array().elementType(type),
    objectOf(type):: self.object().elementType(type),
    arrayOfAny(types):: self.array().elementTypeAnyOf(types),
    objectOfAny(types):: self.object().elementTypeAnyOf(types),

    gt(bound):: self + { gt_::: bound },
    gte(bound):: self + { gte_::: bound },
    lt(bound):: self + { lt_::: bound },
    lte(bound):: self + { lte_::: bound },
    neq(value):: self + { neq_+::: [value] },
    oneOf(values):: self + { one_of_::: values },

    nonEmpty():: self + {
      non_empty_::: true,
      // If type_any_of is unset, set it to the types that are valid for std.length()
      type_any_of_::: utils.ifNull(super.type_any_of_, ['string', 'array', 'object'])
    },

    check(check)::
      assert std.type(check) == 'function' : 'validate.FieldValidator.check(): `check` argument should be a function, found `%s`' % [std.type(check)];
      self + { check_::: check },

    child():: self + { child_::: true },
    children():: self + { children_::: true },
    ignoreNulls():: self + { ignore_nulls_::: true },
  },

  field(fieldname):: $.FieldValidator + {
    fieldname: fieldname,
  },

  MultiFieldValidator: $.Validator + {
    local this = self,

    fields: [],

    exclusive_: false,
    require_one_: false,
    require_all_: false,

    child_: false,
    children_: false,
    check_: null,

    validate(obj, options={})::
      local presence = utils.fold(
        this.fields,
        {
          unset: [],
          null_valued: [],
          present: [],
        },
        function(res, field)
          if !std.objectHasAll(obj, field)
          then res + {
            unset+: [field],
          }
          else if obj[field] == null
          then res + {
            null_valued+: [field],
          }
          else res + {
            present+: [field],
          },
      );

      if std.length(presence.unset) > 0
      then $.ValidationResult.failure('Validated field `%s` is unset' % [presence.unset[0]])

      else if self.exclusive_ && std.length(presence.present) > 1
      then $.ValidationResult.failure('Multiple mutually exclusive fields set: %s' % [formatListOfStrings(presence.present)])

      else if self.require_one_ && std.length(presence.present) < 1
      then $.ValidationResult.failure('All fields in set %s are null, expected %s' % [formatListOfStrings(presence.present), if this.exclusive_ then 'exactly one' else 'at least one'])

      else if self.require_all_ && std.length(presence.null_valued) > 0
      then $.ValidationResult.failure('Required fields %s are null' % [formatListOfStrings(presence.null_valued)])

      else $.ValidationResult.success(),
      
    exclusive():: self + { exclusive_: true },
    requireOne():: self + { require_one_: true },
    requireAll():: self + { require_all_: true },

    // TODO
    child():: assert false : 'validate.MultiFieldValidator.child(): Not implemented'; null,
    children():: assert false : 'validate.MultiFieldValidator.children(): Not implemented'; null,
    check():: assert false : 'validate.MultiFieldValidator.check(): Not implemented'; null,
      
  },

  fields(fieldnames):: $.MultiFieldValidator + {
    fields: fieldnames,
  },
}