{
  ifNull(val, default)::
    if val == null then default else val,

  ifNotNull(val, output_if_not_null, output_if_null=null)::
    if val != null then output_if_not_null else output_if_null,

  // Empty => std.length(input) == 0, not std.isEmpty() which only accepts strings
  ifNotEmpty(val, output_if_not_empty, output_if_empty=null)::
    if std.length(val) > 0 then output_if_not_empty else output_if_empty,

  elseNull(cond, output_if_true)::
    if cond then output_if_true else null,

  // TODO: delete this after migrating usages to elseNull()
  ifTrue(cond, output_if_true, output_if_false=null)::
    if cond then output_if_true else output_if_false,

  singletonArrayIf(cond, elem)::
    if cond then [elem] else [],

  singletonArrayIfNotNull(elem)::
    if elem != null then [elem] else [],

  nullOrEmpty(val)::
    if val == null then true
    else if std.type(val) == 'string' then val == ''
    else if std.type(val) == 'array' then val == []
    else if std.type(val) == 'object' then val == {}
    else false,

  fieldNameIfHas(obj, f, default=null)::
    if std.objectHas(obj, f) then f else default,

  capitalize(str)::
    if std.isEmpty(str) then str else
      std.asciiUpper(std.substr(str, 0, 1)) + std.substr(str, 1, std.length(str) - 1),

  titleCase(str)::
    local words = std.split(str, ' ');
    local capitalized_words = std.map($.capitalize, words);
    std.join(capitalized_words, ' '),

  // Returns an object with a field for each unique value of f(elem) containing an
  // array of all provided elements with that value.
  // f must return a string.
  group(f, elems)::
    std.foldl(function(res, elem) (
      local val = f(elem);
      assert std.type(val) == 'string' : 'utils.group(): Grouping function returned non-string type %s' % [std.type(val)];
      res + { [val]+: [elem] }
    ), elems, {}),

  // Returns an object with a field for each unique value of elem.<fieldname>,
  // containing an array of all provided elements with that field value.
  groupByField(elems, fieldname):: $.group(function(x) std.get(x, fieldname), elems),

  // Return a clone of an object with the given fields removed.
  // Only includes non-hidden fields due to jsonnet limitation, see
  // https://github.com/google/jsonnet/issues/312#issuecomment-1156321480.
  // std.objectRemoveKey() will be available in a future jsonnet releases to
  // improve this.
  withoutFields(obj, fields=[])::
    local removedFieldSet = {
      [f]: true
      for f in fields
    };
    {
      [f]: obj[f]
      for f in std.objectFields(obj)
      if !std.get(removedFieldSet, f, false)
    },

  // Wrapper around std.trace(). Prints string representation of input and
  // returns it unchanged.
  logged(val, label=''):: std.trace(
    local pretty_val =
      if std.type(val) == 'object' || std.type(val) == 'array'
      then std.manifestJsonEx(val, '  ')
      else std.toString(val);
    #local pretty_val = manifest.manifest(val);
    if label == '' then pretty_val
    else '%s: %s' % [label, pretty_val],
    val,
  ),

  // If cond is true, log the provided value. Return it unchanged either way.
  maybeLogged(val, cond, label='')::
    if cond then $.logged(val, label) else val,

  // Normalize input that may be an array, interpretting a non-array value as
  // a singleton array and null as an empty array.
  asArray(val)::
    if std.type(val) == 'array' then
      val
    else if val == null then
      []
    else
      [val],

  coerceToArray(array_or_object, include_hidden=false)::
    // It might make sense to have this accept scalar values, wrapping them as
    // single-element arrays, but that could get confusing since it's ambiguous
    // whether objects should be wrapped in arrays or have their values
    // extracted. The main point of this function is to let objects be used as
    // arrays, rather than to let scalar values be used for array arguments as
    // a convenience
    assert std.member(['array', 'object'], std.type(array_or_object)) : 'utils.coerceToArray(): Input should be either an array or object, found %s' % [std.type(array_or_object)];
    if std.type(array_or_object) == 'array' then
      array_or_object
    else if include_hidden then
      std.objectValuesAll(array_or_object)
    else
      std.objectValues(array_or_object),

  // Flattens an array one level
  flatten(arr)::
    std.foldl(
      function(res, elem)
        if std.type(elem) == 'array'
        then res + elem
        else res + [elem],
      arr,
      [],
    ),

  // Gets the last element of the array, or default if the array is empty
  last(arr, default=null)::
    local length = std.length(arr);
    if length == 0 then default
    else arr[length - 1],

  // Merge non-hidden fields from two objects by value only (i.e. ignoring
  // changes that would occur due to changed dependent fields)
  overlay(first, second)::
    {
      [entry.key]: entry.value
      for entry in std.objectKeysValues(first)
    } + {
      [entry.key]: entry.value
      for entry in std.objectKeysValues(second)
    },

  // Jsonnet's std.uniq() function requires an additional call to std.sort() to
  // actually remove all duplicates
  sortedUnique(items, keyFn=function(x) x, keep_null='keep_one')::
    std.uniq(std.sort(items, keyFn), keyFn),

  // Get all unique items without changing order, with options for handling null
  // values.
  // Args:
  //  items - Array of items to take unique values from
  //  keyFn - Function extracting key to determine uniqueness from.
  //  keep_null - Whether to keep values with null keys. Options:
  //    'keep_none'
  //    'keep_one' (default)
  //    'keep_all'
  unique(items, keyFn=function(x) x, keep_null='keep_one')::
    local key_fn_type = std.type(keyFn);
    assert key_fn_type == 'function' : 'utils.unique(): Expected keyFn to be a function, found %s' % [key_fn_type];
    assert std.member(['keep_none', 'keep_one', 'keep_all'], keep_null) : 'utils.unique(): Unexpected value for keep_null: \'%s\'' % [keep_null];
    std.foldl(
      function(res, elem)
        local key = $.ifNotNull(keyFn(elem), std.toString(keyFn(elem)));
        local is_null_key = (key == null);
        local has_preexisting =
          if is_null_key then res.found_null_key
          else std.objectHas(res.values, key);
        local keep =
          if is_null_key && keep_null == 'keep_all' then true
          else if is_null_key && keep_null == 'keep_none' then false
          else !has_preexisting;
        if keep then res + {
          output+: [elem],
          values+: {
            [key]: elem,
          },
          found_null_key: is_null_key || super.found_null_key,
        }
        else res,
      items,
      {
        output: [],
        values: {},
        found_null_key: false,
      },
    ).output,

  formatValueBrief(value, max_characters=40)::
    local raw =
      if std.type(value) == 'string'
      then '\'%s\'' % [value]
      else std.toString(value);
    local len = std.length(raw);
    if len <= max_characters
    then raw
    else '<%s with length %s>' % [std.type(value), len],

  trim(str):: std.stripChars(str, ' \t\n\f\r\u0085\u00A0'),

  slice(arr, index, end, step=1)::
    local index_processed =
      if index >= 0 then index
      else std.length(arr) + index;
    local end_processed =
      if end >= 0 then end
      else std.length(arr) + end;
    std.slice(arr, index_processed, end_processed, step),

  // std.foldl() with different signature. Provided accumulation function should
  // be of form function(partial_result, new_item).
  fold(arr, init, fn)::
    std.foldl(
      fn,
      arr,
      init
    ),

  // std.foldr() with different signature. Provided accumulation function should
  // be of form function(partial_result, new_item).
  foldReverse(arr, init, fn)::
    std.foldr(
      function(res, item) fn(item, res),
      arr,
      init
    ),

  // field access with null checking.
  get(obj, field, default=null)::
    if std.type(field) == 'string' then
      if !std.objectHasAll(obj, field) then default
      else obj[field]
    else if std.type(field) == 'array' then
      if std.length(field) == 0 then obj
      else if !std.objectHasAll(obj, field[0]) then default
      else $.get(obj[field[0]], field[1:], default)
    else error('utils.get(): Expected field to be a string or array, found %s' % [std.type(field)]),

  // Apply each function in fns to value, in order. Each function should be of
  // the form function(partial_result).
  applyAll(value, fns)::
    $.fold(fns, value, function(res, fn) fn(res)),

  isPrimitive(value)::
    std.member(['string', 'number', 'boolean', 'null'], std.type(value)),

  #// Matcher for jsonnetunit with better output for multiline strings
  #MULTILINE_STRING_MATCHER: function(actual, expected)
  #  super.matcher(actual, expected) + {
  #    positiveMessage: |||
  #      FAILED

  #        got:
  #      %s

  #        want:
  #      %s
  #    ||| % [actual, expected],
  #},

  snakeCaseToKebabCase(x):: std.strReplace(x, '_', '-'),

  // Take the first argument that isn't null.
  // This could be done with utils.fold() instead of fake variadics but this way
  // is probably more performant?
  firstNonNull(arg1, arg2, arg3=null, arg4=null)::
    if arg1 != null then
      arg1
    else if arg2 != null then
      arg2
    else if arg3 != null then
      arg3
    else if arg4 != null then
      arg4
    else
      null,
  #firstNonNull(ary)::
  #  utils.fold(
  #    ary,
  #    null,
  #    function(res, item) if res != null then res else item,
  #  ),

  findFirstWithIndex(arr, pred)::
    local initial_state = {
      index: -1,
      value: null,
      found: false,
    };
    local intermediate = $.fold(
      arr,
      initial_state,
      function(res, elem)
        local new_index = res.index + 1;
        if res.found then
          res
        else if pred(elem) then
          {
            index: new_index,
            value: elem,
            found: true,
          }
        else
          res + {
            index: new_index,
          }
    );
    if intermediate.found then intermediate else intermediate + {
      index: -1,
    },

  findFirstWithKey(obj, pred)::
    local initial_state = {
      key: null,
      value: null,
      found: false,
    };
    $.fold(
      std.objectKeysValues(obj),
      initial_state,
      function(res, elem)
        if res.found then
          res
        else if pred(elem.value) then
          {
            key: elem.key,
            value: elem.value,
            found: true,
          }
        else
          initial_state
    ),
  
  findFirstWithIndexOrKey(obj_or_array, pred)::
    local res = 
      if std.isArray(obj_or_array) then
        $.findFirstWithIndex(obj_or_array, pred)
      else if std.isObject(obj_or_array) then
        $.findFirstWithKey(obj_or_array, pred)
      else
        error('findFirstWithIndexOrKey(): Expected object or array, found %s' % [std.type(obj_or_array)]);
    {
      index_or_key: if std.isArray(obj_or_array) then res.index else res.key,
      value: res.value,
      found: res.found
    },
  
  findFirst(obj_or_array, pred)::
    $.findFirstWithIndexOrKey(obj_or_array, pred).value,

  mergeAll(objects)::
    $.fold(objects, {}, function(state, item) state + item),
}
