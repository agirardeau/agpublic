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
      else 'Validation failure:\n  %s' % [self.failure_message],

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

  debugFieldsForObject(obj)::
    utils.fold(
      obj.__validate__,
      {},
      function(res, stanza)
        local stz = private.ValidationStanza + stanza;
        res + stz.debug,
    ),

  // Output is object with fields:
  //  found
  //  index_or_key
  //  value
  findElement(maybe_container, pred, options={})::
    local opts = {
      ignore_null_elements: true,
      maybe_array: false,
    } + options;
    local container =
      if opts.maybe_array && !std.isArray(maybe_container) then
        [maybe_container]
      else if !std.isArray(maybe_container) && !std.isObject(maybe_container) then
        error('validate.private.findElement(): Expected array or object, got `%s`' % [std.typeOf(maybe_container)])
      else
        maybe_container;
    if opts.ignore_null_elements then
      utils.findFirstWithIndexOrKey(container, function(x) x != null && pred(x))
    else
      utils.findFirstWithIndexOrKey(container, pred),

  // Returns a function that checks if a value meets specified type parameters.
  checkType(options={})::
    local opts = {
      type: null,
      type_any_of: null,
      element_type: null,
      element_type_any_of: null,
      ignore_null_elements: true,
      maybe_array: false,
    } + options;
    function(value)
      local element_type_result =
        if opts.element_type == null then
          { found: false }
        else
          private.findElement(value, function(x) std.type(x) != opts.element_type, opts);
      local element_type_any_of_result =
        if opts.element_type_any_of == null then
          { found: false }
        else
          private.findElement(value, function(x) !std.member(opts.element_type_any_of, std.type(x)), opts);

      // Validate options
      if opts.type != null && !std.isString(opts.type) then
        'Invalid type check options, expected `type` to be a string, found %s' % [std.type(opts.type)]
      else if opts.type_any_of != null && !std.isArray(opts.type_any_of) then
        'Invalid type check options, expected `type_any_of` to be an array, found %s' % [std.type(opts.type_any_of)]
      else if opts.element_type != null && !std.isString(opts.element_type) then
        'Invalid type check options, expected `element_type` to be a string, found %s' % [std.type(opts.element_type)]
      else if opts.element_type_any_of != null && !std.isArray(opts.element_type_any_of) then
        'Invalid type check options, expected `element_type_any_of` to be an array, found %s' % [std.type(opts.element_type_any_of)]

      // Validate value
      else if opts.type != null && std.type(value) != opts.type then
        'Found type `%s`, expected `%s`' % [std.type(value), opts.type]
      else if opts.type_any_of != null && !std.member(opts.type_any_of, std.type(value)) then
        'Found type `%s`, expected one of %s' % [std.type(value), formatListOfStrings(opts.type_any_of)]
      else if element_type_result.found then
        'Element `%s` has type `%s`, expected %s' % [
          element_type_result.index_or_key,
          std.type(element_type_result.value),
          opts.element_type,
        ]
      else if element_type_any_of_result.found then
        'Element `%s` has type `%s`, expected one of %s' % [
          element_type_any_of_result.index_or_key,
          std.type(element_type_any_of_result.value),
          formatListOfStrings(opts.element_type_any_of),
        ]
      else null

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

  validated(obj, options={})::
    local res = $.validate(obj, options);
    if !res.is_valid then error(res.describe()) else obj,
  
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

  // I guess this is just an interface right now, it doesn't have logic
  Validator: {
    validate(val, options={}):: $.ValidationResult.failure('Validator has no implementation'),
  },

  // Return a validator checks whether the object passes a custom function. The
  // function should return null if the field is valid, or a string describing
  // the failure if it is invalid.
  funcValidator(fn):: $.Validator + {
    validate(obj, options={})::
      local output = fn(obj);
      if output == null
      then $.ValidationResult.success()
      else $.ValidationResult.failure(output),
  },

  check: {
    // Type checks
    type(type):: private.checkType({ type: type }),
    typeAny(types):: private.checkType({ type_any_of: types }),
    boolean():: self.type('boolean'),
    string():: self.type('string'),
    number():: self.type('number'),
    fn():: self.type('function'),
    array():: self.type('array'),
    object():: self.type('object'),
    container():: self.typeAny(['array', 'object']),

    // Convenience methods for type checking arrays and their elements
    arrayOf(type)::      private.checkType({ type: 'array', element_type: type }),
    arrayOfAny(types)::  private.checkType({ type: 'array', element_type_any_of: types }),
    arrayOfBoolean()::   self.arrayOf('boolean'),
    arrayOfString()::    self.arrayOf('string'),
    arrayOfNumber()::    self.arrayOf('number'),
    arrayOfFunction()::  self.arrayOf('function'),
    arrayOfArray()::     self.arrayOf('array'),
    arrayOfObject()::    self.arrayOf('object'),
    arrayOfContainer():: self.arrayOfAny(['array', 'object']),

    // Convenience methods for type checking objects and their elements
    objectOf(type)::     private.checkType({ type: 'object', element_type: type }),
    objectOfAny(types):: private.checkType({ type: 'object', element_type_any_of: types }),
    objectOfBoolean()::   self.objectOf('boolean'),
    objectOfString()::    self.objectOf('string'),
    objectOfNumber()::    self.objectOf('number'),
    objectOfFunction()::  self.objectOf('function'),
    objectOfArray()::     self.objectOf('array'),
    objectOfObject()::    self.objectOf('object'),
    objectOfContainer():: self.objectOfAny(['array', 'object']),

    // Convenience methods for type checking containers (arrays/objects) and
    // their elements
    containerOf(type)::     private.checkType({ type_any_of: ['array', 'object'], element_type: type }),
    containerOfAny(types):: private.checkType({ type_any_of: ['array', 'object'], element_type_any_of: types }),
    containerOfBoolean()::   self.containerOf('boolean'),
    containerOfString()::    self.containerOf('string'),
    containerOfNumber()::    self.containerOf('number'),
    containerOfFunction()::  self.containerOf('function'),
    containerOfArray()::     self.containerOf('array'),
    containerOfObject()::    self.containerOf('object'),
    containerOfContainer():: self.containerOfAny(['array', 'object']),

    // Convenience methods for type checking fields that treat non-arrays as
    // singleton arrays
    // maybeArrayOfArray and maybeArrayOfContainer are not provided because they
    // are ambiguous
    maybeArrayOf(type):: private.checkType({ element_type: type, maybe_array: true }),
    maybeArrayOfAny(types):: private.checkType({ element_type_any_of: types, maybe_array: true }),
    maybeArrayOfBoolean():: self.maybeArrayOf('boolean'),
    maybeArrayOfString()::   self.maybeArrayOf('string'),
    maybeArrayOfNumber()::   self.maybeArrayOf('number'),
    maybeArrayOfFunction():: self.maybeArrayOf('function'),
    maybeArrayOfObject()::   self.maybeArrayOf('object'),

    // Check bounds
    gt(bound):: function(x) utils.ifTrue(x <= bound, 'Value `%s` is not greater than bound `%s`' % [x, bound]),
    gte(bound):: function(x) utils.ifTrue(x < bound, 'Value `%s` is not greater than or equal to bound `%s`' % [x, bound]),
    lt(bound):: function(x) utils.ifTrue(x >= bound, 'Value `%s` is not less than bound `%s`' % [x, bound]),
    lte(bound):: function(x) utils.ifTrue(x > bound, 'Value `%s` is not less than or equal to bound `%s`' % [x, bound]),
    neq(value):: function(x) utils.ifTrue(x == value, 'Value `%s` is disallowed' % [value]),
    oneOf(values):: function(x) utils.ifTrue(!std.member(values, x), 'Value `%s` is not one of the expected options %s' % [x, formatListOfStrings([std.toString(x) for x in values])]),

    // Check that a given value is non-empty, passing if the value is not a type
    // that doesn't have a length (types other than string, array, and object)
    nonEmpty():: function(x)
      local type_has_length = std.member(['string', 'array', 'object'], std.type(x));
      utils.ifTrue(type_has_length && std.length(x) == 0, 'Value has length 0, expected non-empty'),
  },

  // Performs validations against a particular field of an object being validated
  FieldValidator: $.Validator + {
    local this = self,

    fieldname: null,

    value_checks:: [],
    element_checks:: [],

    required_:: false,
    maybe_array_:: false,
    child_:: false,
    children_:: false,
    ignore_nulls_:: false,

    // Validate that the field is set to a non-null value
    required():: self + { required_::: true },

    // Validate that the field passes a custom check function. The function
    // should return null if the field is valid, or a string describing the
    // failure if it is invalid.
    check(check)::
      assert std.type(check) == 'function' : 'validate.FieldValidator.check(): Argument should be a function, found `%s`' % [std.type(check)];
      self + { value_checks+:: [check] },

    // Validate that elements of the field pass a custom check function. The
    // function should return null if the field is valid, or a string describing
    // the failure if it is invalid.
    checkElements(check)::
      assert std.type(check) == 'function' : 'validate.FieldValidator.checkElements(): Argument should be a function, found `%s`' % [std.type(check)];
      self + { element_checks+:: [check] },

    // Validate non-array values as though they are singleton arrays
    maybeArray():: self + { maybe_array_::: true },

    // Whether null values are ignored when type checking array/object elements
    ignoreNulls():: self + { ignore_nulls_::: true },

    // If set, validation will be performed on the child field if it is an
    // object. To reject non-objects, call object() separately.
    child():: self + { child_::: true },

    // If set, validation will be performed on elements of the child field if
    // they are objects. To reject non-objects, call arrayOf('object') or
    // similar separately.
    children():: self + { children_::: true },

    // Validate that elements of the (array or object) field are of the given
    // type.
    // 
    // FieldValidator handles type checking container elements differently
    // than the checks in validate.check - instead of one check that checks both
    // the container type and the element type, a separate type check is added
    // to both the `value_checks` and `element_checks` properties.
    elementType(type):: self.checkElements($.check.type(type)),
    elementTypeAny(types):: self.checkElements($.check.typeAny(types)),

    // Convenience methods for adding checks provided in $.check
    type(type)::     self.check($.check.type(type)),
    typeAny(types):: self.check($.check.typeAny(types)),
    boolean()::      self.type('boolean'),
    string()::       self.type('string'),
    number()::       self.type('number'),
    fn()::           self.type('function'),
    array()::        self.type('array'),
    object()::       self.type('object'),
    container()::    self.typeAny(['array', 'object']),

    arrayOf(type)::      self.array().elementType(type),
    arrayOfAny(types)::  self.array().elementTypeAny(types),
    arrayOfBoolean()::   self.arrayOf('boolean'),
    arrayOfString()::    self.arrayOf('string'),
    arrayOfNumber()::    self.arrayOf('number'),
    arrayOfFunction()::  self.arrayOf('function'),
    arrayOfArray()::     self.arrayOf('array'),
    arrayOfObject()::    self.arrayOf('object'),
    arrayOfContainer():: self.arrayOfAny(['array', 'object']),

    objectOf(type)::      self.object().elementType(type),
    objectOfAny(types)::  self.object().elementTypeAny(types),
    objectOfBoolean()::   self.objectOf('boolean'),
    objectOfString()::    self.objectOf('string'),
    objectOfNumber()::    self.objectOf('number'),
    objectOfFunction()::  self.objectOf('function'),
    objectOfArray()::     self.objectOf('array'),
    objectOfObject()::    self.objectOf('object'),
    objectOfContainer():: self.objectOfAny(['array', 'object']),

    containerOf(type)::      self.container().elementType(type),
    containerOfAny(types)::  self.container().elementTypeAny(types),
    containerOfBoolean()::   self.containerOf('boolean'),
    containerOfString()::    self.containerOf('string'),
    containerOfNumber()::    self.containerOf('number'),
    containerOfFunction()::  self.containerOf('function'),
    containerOfArray()::     self.containerOf('array'),
    containerOfObject()::    self.containerOf('object'),
    containerOfContainer():: self.containerOfAny(['array', 'object']),

    gt(bound):: self.check($.check.gt(bound)),
    gte(bound):: self.check($.check.gte(bound)),
    lt(bound):: self.check($.check.lt(bound)),
    lte(bound):: self.check($.check.lte(bound)),
    neq(value):: self.check($.check.neq(value)),
    oneOf(values):: self.check($.check.oneOf(values)),

    nonEmpty():: self.check($.check.nonEmpty()),

    // Convenience methods for type checking fields that treat non-arrays as
    // singleton arrays
    //
    // maybeArrayOfArray and maybeArrayOfContainer are not provided because they
    // are ambiguous
    maybeArrayOf(type)::     self.maybeArray().elementType(type),
    maybeArrayOfAny(types):: self.maybeArray().elementTypeAny(types),
    maybeArrayOfBoolean()::  self.maybeArrayOf('boolean'),
    maybeArrayOfString()::   self.maybeArrayOf('string'),
    maybeArrayOfNumber()::   self.maybeArrayOf('number'),
    maybeArrayOfFunction():: self.maybeArrayOf('function'),
    maybeArrayOfObject()::   self.maybeArrayOf('object'),

    validate(obj, options={})::
      
      local value = if std.objectHasAll(obj, self.fieldname) then obj[self.fieldname] else null;
      local found_type = std.type(value);

      local value_check_result = utils.fold(
        self.value_checks,
        null,
        function(res, check) utils.firstNonNull(res, check(value)),
      );
      local element_container =
        if std.isArray(value) then
          value
        else if self.maybe_array_ then
          [value]
        else if std.isObject(value) then
          value
        else
          [];
      local element_check_result = utils.fold(
        // Each check
        self.element_checks,
        null,
        function(res, check)
          // Each element
          local find_res = private.findElement(
            element_container,
            function(x) check(x) != null,
            { ignore_null_elements: this.ignore_nulls_ },
          );
          local new_res = utils.ifTrue(find_res.found, 'Element `%s`:\n      %s' % [find_res.index_or_key, check(find_res.value)]);
          utils.firstNonNull(res, new_res),
      );

      #local findInvalidElementType(arr_or_obj, element_type_or_types, ignore_nulls) =
      #  local is_array = std.type(arr_or_obj) == 'array';
      #  local checkType(type) =
      #    if type == 'null' then ignore_nulls
      #    else if std.type(element_type_or_types) == 'string' then type == element_type_or_types
      #    else std.member(element_type_or_types, type);
      #  utils.fold(
      #    if is_array then arr_or_obj else std.objectKeysValuesAll(arr_or_obj),
      #    {
      #      index: -1,
      #      wrong_type: null,
      #    },
      #    function(res, elem)
      #      local type = if is_array then std.type(elem) else std.type(elem.value);
      #      if res.wrong_type != null then res
      #      else {
      #        index: if is_array then res.index + 1 else elem.key,
      #        wrong_type: if !checkType(type) then type else null,
      #      },
      #  );
      #local element_type_check = findInvalidElementType(value, self.element_type_, self.ignore_nulls_);
      #local element_type_any_of_check = findInvalidElementType(value, self.element_type_any_of_, self.ignore_nulls_);

      // Always reject unset fields with validation configured to catch typos
      // in field names
      if !std.objectHasAll(obj, self.fieldname)
      then $.ValidationResult.failure('Validated field `%s` is unset' % [self.fieldname])

      else if self.required_ && value == null
      then $.ValidationResult.failure('Required field `%s` is null' % [self.fieldname])

      else if value == null
      then $.ValidationResult.success()

      else if value_check_result != null
      then $.ValidationResult.failure('Field `%s`:\n    %s' % [self.fieldname, value_check_result])

      else if element_check_result != null
      then $.ValidationResult.failure('Field `%s`:\n    %s' % [self.fieldname, element_check_result])

      #else if self.type_ != null && found_type != self.type_
      #then $.ValidationResult.failure('Field `%s` has type `%s`, expected `%s`' % [this.fieldname, found_type, self.type_])

      #else if self.type_any_of_ != null && !std.member(self.type_any_of_, found_type)
      #then $.ValidationResult.failure('Field `%s` has type `%s`, expected one of %s' % [this.fieldname, found_type, formatListOfStrings(self.type_any_of_)])

      #else if self.element_type_ != null && element_type_check.wrong_type != null
      #then $.ValidationResult.failure('Field `%s` element `%s` has type `%s`, expected `%s`' % [this.fieldname, element_type_check.index, element_type_check.wrong_type, self.element_type_])

      #else if self.element_type_any_of_ != null && element_type_any_of_check.wrong_type != null
      #then $.ValidationResult.failure('Field `%s` element `%s` has type `%s`, expected one of %s' % [this.fieldname, element_type_any_of_check.index, element_type_any_of_check.wrong_type, formatListOfStrings(self.element_type_any_of_)])

      #else if self.gt_ != null && value <= self.gt_
      #then $.ValidationResult.failure('Field `%s` has value `%s`, not greater than bound `%s`' % [this.fieldname, value, self.gt_])

      #else if self.gte_ != null && value < self.gte_
      #then $.ValidationResult.failure('Field `%s` has value `%s`, not greater than or equal to bound `%s`' % [this.fieldname, value, self.gte_])

      #else if self.lt_ != null && value >= self.lt_
      #then $.ValidationResult.failure('Field `%s` has value `%s`, not less than bound `%s`' % [this.fieldname, value, self.lt_])

      #else if self.lte_ != null && value > self.lte_
      #then $.ValidationResult.failure('Field `%s` has value `%s`, not less than or equal to bound `%s`' % [this.fieldname, value, self.lte_])

      #else if std.member(self.neq_, value)
      #then $.ValidationResult.failure('Field `%s` has disallowed value `%s`' % [this.fieldname, value])

      #else if self.one_of_ != null && !std.member(self.one_of_, value)
      #then $.ValidationResult.failure('Field `%s` has value `%s`, expected one of %s' % [this.fieldname, value, formatListOfStrings([utils.formatValueBrief(x) for x in self.one_of_])])

      #else if self.non_empty_ && std.length(value) == 0
      #then $.ValidationResult.failure('Field `%s` is empty %s' % [this.fieldname, std.type(value)])

      #else if self.check_ != null && self.check_(value) != null
      #then $.ValidationResult.failure('Field `%s` failed check function with message: %s' % [this.fieldname, self.check_(value)])

      else if self.child_ && std.isObject(value)
      then $.validate(value).withFieldContext(private.ValidationContext.FieldContext + {
        name: this.fieldname,
      })

      else if self.children_ && (found_type == 'array' || self.maybe_array_)
      then utils.fold(
        utils.asArray(value),
        {
          index: 0,
          result: $.ValidationResult.success(),
        },
        function(res, child) {
          index: res.index + 1,
          result:
            // Short circuit if an invalid child was already found
            if !res.result.is_valid || !std.isObject(child)
            then res.result
            else $.validate(child).withFieldContext(private.ValidationContext.FieldContext + {
              name: this.fieldname,
              element_index: res.index,
            }),
        },
      ).result

      else if self.children_ && found_type == 'object'
      #then utils.logged(utils.fold(
      then utils.fold(
        std.objectKeysValues(value),
        $.ValidationResult.success(),
        function(res, child_entry)
          // Short circuit if an invalid child was already found
          if !res.is_valid || !std.isObject(child_entry.value)
          then res
          else $.validate(child_entry.value).withFieldContext(private.ValidationContext.FieldContext + {
            name: this.fieldname,
            element_index: child_entry.key,
          }),
      #), 'CHILDREN_RESULT')
      )

      else $.ValidationResult.success(),
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